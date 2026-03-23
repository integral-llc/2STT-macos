import AVFoundation

public protocol AudioCapturing: AnyObject, Sendable {
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }
    func start() throws
    func stop()
}
