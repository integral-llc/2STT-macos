import CoreAudio
import AVFoundation
import AudioToolbox
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualAudioTranscriber", category: "SystemAudioCapture")

@Observable
final class SystemAudioCaptureManager: AudioCapturing, @unchecked Sendable {
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start() throws {
        guard !isRunning else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.eugenerat.DualAudioTranscriber"
        log.fault("Creating CATapDescription - excluding bundleID=\(bundleID)")

        // Use default init + properties. The stereoGlobalTapButExcludeProcesses
        // initializer takes CoreAudio process AudioObjectIDs (NOT PIDs).
        // On macOS 26, bundleIDs is the simpler approach.
        let tapDescription = CATapDescription()
        tapDescription.isMixdown = true      // stereo mixdown
        tapDescription.isExclusive = true     // exclude listed processes
        tapDescription.bundleIDs = [bundleID] // exclude our own audio

        let tapUUID = tapDescription.uuid.uuidString
        log.fault("Tap UUID=\(tapUUID) mixdown=\(tapDescription.isMixdown) exclusive=\(tapDescription.isExclusive)")

        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        log.fault("AudioHardwareCreateProcessTap status: \(tapStatus) tapID: \(tapID)")
        guard tapStatus == noErr else {
            log.error("Tap creation FAILED: OSStatus \(tapStatus)")
            throw AudioCaptureError.tapCreationFailed(tapStatus)
        }
        self.tapObjectID = tapID

        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var format = AudioStreamBasicDescription()
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let formatStatus = AudioObjectGetPropertyData(
            tapID, &formatAddress, 0, nil, &formatSize, &format
        )
        log.fault("Tap format read status: \(formatStatus)")
        guard formatStatus == noErr else {
            log.error("Format read FAILED: OSStatus \(formatStatus)")
            cleanup()
            throw AudioCaptureError.formatReadFailed(formatStatus)
        }

        log.fault("Tap format: sampleRate=\(format.mSampleRate) channels=\(format.mChannelsPerFrame) bitsPerChannel=\(format.mBitsPerChannel) formatFlags=\(format.mFormatFlags) bytesPerFrame=\(format.mBytesPerFrame)")

        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "DualAudioTranscriber_Tap",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey as String: true,
        ]

        var aggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(
            aggregateDesc as CFDictionary, &aggID
        )
        log.fault("Aggregate device status: \(aggStatus) deviceID: \(aggID)")
        guard aggStatus == noErr else {
            log.error("Aggregate device FAILED: OSStatus \(aggStatus)")
            cleanup()
            throw AudioCaptureError.aggregateDeviceFailed(aggStatus)
        }
        self.aggregateDeviceID = aggID

        guard let avFormat = AVAudioFormat(streamDescription: &format) else {
            log.error("AVAudioFormat creation FAILED from stream description")
            cleanup()
            throw AudioCaptureError.formatReadFailed(formatStatus)
        }
        log.fault("AVAudioFormat created: \(avFormat)")

        let capturedFormat = format
        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID, aggID, nil
        ) { [weak self] _, inInputData, inInputTime, _, _ in
            guard let self else { return }

            let channelCount = Int(capturedFormat.mChannelsPerFrame)
            guard channelCount > 0 else { return }

            let isNonInterleaved = capturedFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inInputData)
            )
            guard buffers.count > 0 else { return }

            // For non-interleaved: each AudioBuffer holds one channel,
            // mDataByteSize is per-channel. For interleaved: single buffer
            // with all channels, mDataByteSize is total.
            let frameCount: AVAudioFrameCount
            if isNonInterleaved {
                frameCount = AVAudioFrameCount(
                    buffers[0].mDataByteSize / UInt32(MemoryLayout<Float>.size)
                )
            } else {
                frameCount = AVAudioFrameCount(
                    buffers[0].mDataByteSize /
                    UInt32(MemoryLayout<Float>.size * channelCount)
                )
            }
            guard frameCount > 0 else { return }

            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: avFormat,
                frameCapacity: frameCount
            ) else { return }
            pcmBuffer.frameLength = frameCount

            guard let dstData = pcmBuffer.floatChannelData else { return }

            if isNonInterleaved {
                // Copy each channel from its own AudioBuffer
                for ch in 0..<min(channelCount, buffers.count) {
                    if let src = buffers[ch].mData {
                        memcpy(dstData[ch], src, Int(buffers[ch].mDataByteSize))
                    }
                }
            } else if channelCount == 1 {
                if let src = buffers[0].mData {
                    memcpy(dstData[0], src, Int(buffers[0].mDataByteSize))
                }
            } else {
                // Interleaved stereo - deinterleave to planar
                if let src = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                    for frame in 0..<Int(frameCount) {
                        for ch in 0..<channelCount {
                            dstData[ch][frame] = src[frame * channelCount + ch]
                        }
                    }
                }
            }

            let audioTime = AVAudioTime(hostTime: inInputTime.pointee.mHostTime)
            self.onAudioBuffer?(pcmBuffer, audioTime)
        }

        log.fault("IO proc status: \(ioStatus)")
        guard ioStatus == noErr, let procID else {
            log.error("IO proc FAILED: OSStatus \(ioStatus)")
            cleanup()
            throw AudioCaptureError.ioProcFailed(ioStatus)
        }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(aggID, procID)
        log.fault("Device start status: \(startStatus)")
        guard startStatus == noErr else {
            log.error("Device start FAILED: OSStatus \(startStatus)")
            cleanup()
            throw AudioCaptureError.deviceStartFailed(startStatus)
        }
        isRunning = true
        log.fault("System audio capture started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cleanup()
        log.fault("System audio capture stopped")
    }

    private func cleanup() {
        if let procID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapObjectID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapObjectID)
        }
        tapObjectID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
    }

    deinit {
        if isRunning { cleanup() }
    }
}
