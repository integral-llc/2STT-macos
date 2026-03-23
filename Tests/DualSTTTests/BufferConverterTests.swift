import AVFoundation
@testable import DualSTT
import Foundation
import Testing

struct BufferConverterTests {
    private func makeTargetFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
    }

    private func makeSineBuffer(
        sampleRate: Double,
        channels: UInt32,
        commonFormat: AVAudioCommonFormat = .pcmFormatFloat32,
        frameCount: AVAudioFrameCount = 4800,
        frequency: Float = 440.0
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if commonFormat == .pcmFormatFloat32, let channelData = buffer.floatChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    let phase = Float(frame) / Float(sampleRate) * frequency * 2.0 * .pi
                    channelData[ch][frame] = sinf(phase)
                }
            }
        } else if commonFormat == .pcmFormatInt16, let channelData = buffer.int16ChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    let phase = Float(frame) / Float(sampleRate) * frequency * 2.0 * .pi
                    channelData[ch][frame] = Int16(sinf(phase) * Float(Int16.max / 2))
                }
            }
        }

        return buffer
    }

    @Test
    func `passthrough returns same buffer instance when formats match`() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let buffer = makeSineBuffer(
            sampleRate: 16000,
            channels: 1,
            commonFormat: .pcmFormatInt16,
            frameCount: 1600
        )

        let result = converter.convert(buffer)

        #expect(result === buffer)
    }

    @Test
    func `downsamples 48kHz to 16kHz`() throws {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 48000)

        let result = converter.convert(buffer)

        #expect(result != nil)
        let expected = AVAudioFrameCount(16000)
        // AVAudioConverter adds filter latency frames; allow 512-frame tolerance
        #expect(try abs(Int(#require(result?.frameLength)) - Int(expected)) <= 512)
        #expect(result?.format.sampleRate == 16000)
    }

    @Test
    func `downsamples 44.1kHz to 16kHz`() throws {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(sampleRate: 44100, channels: 1, frameCount: 44100)

        let result = converter.convert(buffer)

        #expect(result != nil)
        let expected = AVAudioFrameCount(16000)
        #expect(try abs(Int(#require(result?.frameLength)) - Int(expected)) <= 512)
        #expect(result?.format.sampleRate == 16000)
    }

    @Test
    func `converts stereo to mono`() {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(sampleRate: 16000, channels: 2, frameCount: 1600)

        let result = converter.convert(buffer)

        #expect(result != nil)
        #expect(result?.format.channelCount == 1)
    }

    @Test
    func `converts Float32 to Int16`() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let buffer = makeSineBuffer(
            sampleRate: 16000,
            channels: 1,
            commonFormat: .pcmFormatFloat32,
            frameCount: 1600
        )

        let result = converter.convert(buffer)

        #expect(result != nil)
        #expect(result?.format.commonFormat == .pcmFormatInt16)
    }

    @Test
    func `full conversion: Float32 48kHz stereo to Int16 16kHz mono`() throws {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(
            sampleRate: 48000,
            channels: 2,
            commonFormat: .pcmFormatFloat32,
            frameCount: 48000
        )

        let result = converter.convert(buffer)

        #expect(result != nil)
        #expect(result?.format.sampleRate == 16000)
        #expect(result?.format.channelCount == 1)
        #expect(result?.format.commonFormat == .pcmFormatInt16)
        // Multi-parameter conversion (rate + channels + format) has higher filter latency
        let expected = 16000
        #expect(try abs(Int(#require(result?.frameLength)) - expected) <= 2000)
        #expect(try #require(result?.frameLength) > 0)
    }

    @Test
    func `reuses converter for consecutive same-format buffers`() {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer1 = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)
        let buffer2 = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)

        let result1 = converter.convert(buffer1)
        let result2 = converter.convert(buffer2)

        #expect(result1 != nil)
        #expect(result2 != nil)
        #expect(result1?.format == result2!.format)
    }

    @Test
    func `recreates converter when input format changes mid-stream`() {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer48k = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)
        let buffer441k = makeSineBuffer(sampleRate: 44100, channels: 1, frameCount: 4410)

        let result1 = converter.convert(buffer48k)
        let result2 = converter.convert(buffer441k)

        #expect(result1 != nil)
        #expect(result2 != nil)
        #expect(result1?.format.sampleRate == 16000)
        #expect(result2?.format.sampleRate == 16000)
    }

    @Test
    func `handles single-frame buffer without crash`() {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 1)

        let result = converter.convert(buffer)

        #expect(result != nil)
    }

    @Test
    func `handles large 10-second buffer`() throws {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(
            sampleRate: 48000,
            channels: 1,
            frameCount: 480_000
        )

        let result = converter.convert(buffer)

        #expect(result != nil)
        let expected = AVAudioFrameCount(160_000)
        #expect(try abs(Int(#require(result?.frameLength)) - Int(expected)) <= 512)
    }

    @Test
    func `output contains non-zero audio data`() throws {
        let converter = BufferConverter(targetFormat: makeTargetFormat())
        let buffer = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)

        let result = converter.convert(buffer)

        #expect(result != nil)
        let int16Data = try #require(result?.int16ChannelData)
        let frameLength = try Int(#require(result?.frameLength))
        var hasNonZero = false
        for i in 0..<frameLength {
            if int16Data[0][i] != 0 {
                hasNonZero = true
                break
            }
        }
        #expect(hasNonZero)
    }

    @Test
    func `1000 rapid conversions without crash or leak`() {
        let converter = BufferConverter(targetFormat: makeTargetFormat())

        for _ in 0..<1000 {
            let buffer = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 480)
            let result = converter.convert(buffer)
            #expect(result != nil)
        }
    }
}
