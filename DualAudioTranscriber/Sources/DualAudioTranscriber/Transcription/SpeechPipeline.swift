import Speech
import AVFoundation
import CoreMedia
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

    var onTranscript: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    init(source: AudioSource) {
        self.source = source
    }

    func prepare(locale: Locale = Locale(identifier: "en-US")) async throws {
        log.fault("[\(self.source.rawValue)] prepare() locale=\(locale.identifier)")

        // Verify locale support
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw TranscriptionError.localeNotSupported(locale)
        }
        log.fault("[\(self.source.rawValue)] resolved locale=\(resolvedLocale.identifier)")

        // Create transcriber
        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            preset: .progressiveTranscription
        )
        self.transcriber = transcriber

        // Ensure model is downloaded
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            log.fault("[\(self.source.rawValue)] downloading speech model...")
            try await request.downloadAndInstall()
            log.fault("[\(self.source.rawValue)] model download complete")
        }

        // Verify model is installed
        let installed = await SpeechTranscriber.installedLocales
        let modelReady = installed.contains {
            $0.identifier(.bcp47) == resolvedLocale.identifier(.bcp47)
        }
        log.fault("[\(self.source.rawValue)] modelReady=\(modelReady) installed=\(installed.map { $0.identifier })")
        guard modelReady else {
            throw TranscriptionError.modelNotInstalled(resolvedLocale)
        }

        // Create input stream for feeding audio buffers
        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = continuation

        // Create analyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        log.fault("[\(self.source.rawValue)] SpeechAnalyzer created")

        // Consume transcription results
        resultsTask = Task { [weak self, source = self.source] in
            log.fault("[\(source.rawValue)] results task ENTERED")
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    let rangeEnd = CMTimeRangeGetEnd(result.range)
                    let isFinal = CMTIME_IS_VALID(result.resultsFinalizationTime)
                        && CMTimeCompare(rangeEnd, result.resultsFinalizationTime) <= 0
                    self.onTranscript?(text, isFinal)
                }
                log.fault("[\(source.rawValue)] results stream ended")
            } catch is CancellationError {
                log.fault("[\(source.rawValue)] results cancelled")
            } catch {
                log.fault("[\(source.rawValue)] results ERROR: \(error)")
                self?.onError?("[\(source.rawValue)] Transcription error: \(error.localizedDescription)")
            }
        }

        // Start analysis - blocks until input stream finishes
        analysisTask = Task { [analyzer, source = self.source] in
            log.fault("[\(source.rawValue)] analyzeSequence ENTERED")
            do {
                let _ = try await analyzer.analyzeSequence(inputSequence)
                log.fault("[\(source.rawValue)] analyzeSequence finished")
            } catch is CancellationError {
                log.fault("[\(source.rawValue)] analyzeSequence cancelled")
            } catch {
                log.fault("[\(source.rawValue)] analyzeSequence ERROR: \(error)")
            }
        }

        isActive = true
        log.fault("[\(self.source.rawValue)] prepare() DONE")
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        guard isActive else { return }
        inputContinuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func finalize() async {
        guard isActive else { return }
        isActive = false
        log.fault("[\(self.source.rawValue)] finalize()")

        // End the input stream so analyzeSequence can complete
        inputContinuation?.finish()

        // Finalize pending results
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
    }
}
