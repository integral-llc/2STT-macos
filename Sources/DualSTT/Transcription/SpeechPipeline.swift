import AVFoundation
import os.log
@preconcurrency import Speech

private let log = Logger(subsystem: "com.zintegral.DualSTT", category: "SpeechPipeline")

public final class SpeechPipeline: @unchecked Sendable {
    public let source: AudioSource
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var isActive = false

    private let lock = NSLock()

    private var bufferConverter: BufferConverter?

    public var onTranscript: (@Sendable (String, Bool) -> Void)?
    public var onError: (@Sendable (String) -> Void)?

    public init(source: AudioSource) {
        self.source = source
    }

    public func prepare(locale: Locale = Locale(identifier: "en-US")) async throws {
        log.fault("[\(self.source.rawValue)] prepare() locale=\(locale.identifier)")

        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        )
        else {
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
        )
        else {
            throw TranscriptionError.modelNotInstalled(resolvedLocale)
        }
        self.bufferConverter = BufferConverter(targetFormat: bestFormat)
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

    public func appendAudio(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isActive, let bufferConverter else { return }
        guard let converted = bufferConverter.convert(buffer) else { return }
        inputContinuation?.yield(AnalyzerInput(buffer: converted))
    }

    public func finalize() async {
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
        bufferConverter = nil
    }
}
