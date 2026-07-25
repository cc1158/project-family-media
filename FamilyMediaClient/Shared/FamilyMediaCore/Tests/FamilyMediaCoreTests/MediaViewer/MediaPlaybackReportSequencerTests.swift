import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaPlaybackReportSequencerTests {
    @Test func slowLifecycleRequestKeepsOnlyLatestQueuedProgress() async {
        let sequencer = MediaPlaybackReportSequencer()
        let gate = ReportGate()
        let recorder = ReportEventRecorder()

        sequencer.enqueueLifecycle {
            await recorder.append("started")
            await gate.wait()
        }
        sequencer.enqueueProgress { await recorder.append("progress-1") }
        sequencer.enqueueProgress { await recorder.append("progress-2") }
        sequencer.enqueueProgress { await recorder.append("progress-3") }

        await gate.open()
        await sequencer.waitForPendingReports()

        #expect(await recorder.events == ["started", "progress-3"])
    }

    @Test func stopDropsStaleProgressButRemainsBehindActiveLifecycleRequest() async {
        let sequencer = MediaPlaybackReportSequencer()
        let gate = ReportGate()
        let recorder = ReportEventRecorder()

        sequencer.enqueueLifecycle {
            await recorder.append("started")
            await gate.wait()
        }
        for index in 1...20 {
            sequencer.enqueueProgress {
                await recorder.append("progress-\(index)")
            }
        }
        sequencer.enqueueStop { await recorder.append("stopped") }

        await gate.open()
        await sequencer.waitForPendingReports()

        #expect(await recorder.events == ["started", "stopped"])
    }

    @Test func stopCancelsActiveProgressRequest() async throws {
        let sequencer = MediaPlaybackReportSequencer()
        let recorder = ReportEventRecorder()

        sequencer.enqueueProgress {
            await recorder.append("progress-started")
            do {
                try await Task.sleep(for: .seconds(30))
                await recorder.append("progress-finished")
            } catch is CancellationError {
                await recorder.append("progress-cancelled")
            } catch {
                await recorder.append("progress-failed")
            }
        }
        try await waitUntil { await recorder.events.contains("progress-started") }

        sequencer.enqueueStop { await recorder.append("stopped") }
        await sequencer.waitForPendingReports()

        #expect(await recorder.events == ["progress-started", "progress-cancelled", "stopped"])
    }

    @Test func completedQueueCanProcessAnotherPlaybackLifecycle() async {
        let sequencer = MediaPlaybackReportSequencer()
        let recorder = ReportEventRecorder()

        sequencer.enqueueLifecycle { await recorder.append("started-1") }
        await sequencer.waitForPendingReports()
        sequencer.enqueueStop { await recorder.append("stopped-1") }
        await sequencer.waitForPendingReports()
        sequencer.enqueueLifecycle { await recorder.append("started-2") }
        await sequencer.waitForPendingReports()

        #expect(await recorder.events == ["started-1", "stopped-1", "started-2"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待播放上报事件超时")
    }
}

private actor ReportGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

private actor ReportEventRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
