import Foundation

@MainActor
public protocol MediaAudioSessionManaging: AnyObject {
    func activateForVideoPlayback()
    func deactivateAfterVideoPlayback()
}

@MainActor
public protocol MediaPlaybackSystemEventObserving: AnyObject {
    func start(onPauseRequested: @escaping @MainActor () -> Void)
    func stop()
}

#if canImport(AVFAudio) && (os(iOS) || os(tvOS))
import AVFAudio

@MainActor
public final class SystemMediaAudioSessionManager: MediaAudioSessionManaging {
    public init() {}

    public func activateForVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    public func deactivateAfterVideoPlayback() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
public final class SystemMediaPlaybackEventObserver: MediaPlaybackSystemEventObserving {
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    public init() {}

    public func start(onPauseRequested: @escaping @MainActor () -> Void) {
        stop()
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawValue) == .began
            else {
                return
            }
            Task { @MainActor in onPauseRequested() }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: rawValue) == .oldDeviceUnavailable
            else {
                return
            }
            Task { @MainActor in onPauseRequested() }
        }
    }

    public func stop() {
        let center = NotificationCenter.default
        if let interruptionObserver {
            center.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            center.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }
}
#else
@MainActor
public final class SystemMediaAudioSessionManager: MediaAudioSessionManaging {
    public init() {}
    public func activateForVideoPlayback() {}
    public func deactivateAfterVideoPlayback() {}
}

@MainActor
public final class SystemMediaPlaybackEventObserver: MediaPlaybackSystemEventObserving {
    public init() {}
    public func start(onPauseRequested: @escaping @MainActor () -> Void) {}
    public func stop() {}
}
#endif
