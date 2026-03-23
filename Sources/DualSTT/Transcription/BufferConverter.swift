import AVFoundation
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualSTT", category: "BufferConverter")

final class BufferConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let srcFormat = buffer.format

        // Invalidate converter if the input format changed (e.g. device switch)
        if let existing = converter, existing.inputFormat != srcFormat {
            log.fault("Input format changed, recreating converter")
            converter = nil
        }

        if converter == nil {
            if srcFormat.sampleRate == targetFormat.sampleRate,
               srcFormat.channelCount == targetFormat.channelCount,
               srcFormat.commonFormat == targetFormat.commonFormat {
                // Formats match - passthrough (returns same buffer instance)
                return buffer
            } else if let c = AVAudioConverter(from: srcFormat, to: targetFormat) {
                c.primeMethod = .none
                converter = c
                log
                    .fault(
                        "Converter created: \(srcFormat.sampleRate)Hz \(srcFormat.channelCount)ch -> \(self.targetFormat.sampleRate)Hz \(self.targetFormat.channelCount)ch"
                    )
            } else {
                log.fault("Failed to create converter")
                return nil
            }
        }

        guard let converter else {
            return buffer
        }

        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: capacity
        )
        else { return nil }

        var consumed = false
        let status = converter.convert(to: converted, error: nil) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return converted
    }
}
