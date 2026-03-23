@preconcurrency import Speech
import AVFoundation
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualAudioTranscriber", category: "SpeechPipeline")

final class SpeechPipeline: @unchecked Sendable {
    let source: AudioSource
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var isActive = false

    private let lock = NSLock()

    // Audio format conversion - SpeechAnalyzer requires 16kHz Int16 mono
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    var onTranscript: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    init(source: AudioSource) {
        self.source = source
    }

    func prepare(locale: Locale = Locale(identifier: "en-US")) async throws {
        log.fault("[\(self.source.rawValue)] prepare() locale=\(locale.identifier)")

        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw TranscriptionError.localeNotSupported(locale)
        }

        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            preset: .progressiveTranscription
        )
        self.transcriber = transcriber

        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            log.fault("[\(self.source.rawValue)] downloading speech model...")
            try await request.downloadAndInstall()
        }

        // Get the format SpeechAnalyzer actually wants (16kHz Int16 mono)
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw TranscriptionError.modelNotInstalled(resolvedLocale)
        }
        self.targetFormat = bestFormat
        log.fault("[\(self.source.rawValue)] target format: \(bestFormat.sampleRate)Hz \(bestFormat.channelCount)ch")

        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self, source = self.source] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    self.onTranscript?(text, result.isFinal)
                }
            } catch is CancellationError {
                // expected
            } catch {
                log.fault("[\(source.rawValue)] results ERROR: \(error)")
                self?.onError?("[\(source.rawValue)] \(error.localizedDescription)")
            }
        }

        analysisTask = Task { [analyzer, source = self.source] in
            do {
                try await analyzer.start(inputSequence: inputSequence)
            } catch is CancellationError {
                // expected
            } catch {
                log.fault("[\(source.rawValue)] analyzeSequence ERROR: \(error)")
            }
        }

        isActive = true
        log.fault("[\(self.source.rawValue)] prepare() DONE")
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isActive, let targetFormat else { return }

        let srcFormat = buffer.format

        // Invalidate converter if the input format changed (e.g. device switch)
        if let existing = converter, existing.inputFormat != srcFormat {
            log.fault("[\(self.source.rawValue)] input format changed, recreating converter")
            self.converter = nil
        }

        if converter == nil {
            if srcFormat.sampleRate == targetFormat.sampleRate
                && srcFormat.channelCount == targetFormat.channelCount
                && srcFormat.commonFormat == targetFormat.commonFormat {
                // Formats match - no conversion needed
            } else if let c = AVAudioConverter(from: srcFormat, to: targetFormat) {
                c.primeMethod = .none
                self.converter = c
                log.fault("[\(self.source.rawValue)] converter: \(srcFormat.sampleRate)Hz \(srcFormat.channelCount)ch -> \(targetFormat.sampleRate)Hz \(targetFormat.channelCount)ch")
            } else {
                log.fault("[\(self.source.rawValue)] FAILED to create converter")
                return
            }
        }

        if let converter {
            let ratio = targetFormat.sampleRate / srcFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: capacity
            ) else { return }

            var error: NSError?
            var consumed = false
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error else { return }
            inputContinuation?.yield(AnalyzerInput(buffer: converted))
        } else {
            inputContinuation?.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func finalize() async {
        guard isActive else { return }
        isActive = false

        inputContinuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            log.fault("[\(self.source.rawValue)] finalizeAndFinish error: \(error)")
        }

        resultsTask?.cancel()
        analysisTask?.cancel()
        resultsTask = nil
        analysisTask = nil
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        converter = nil
        targetFormat = nil
    }
}
