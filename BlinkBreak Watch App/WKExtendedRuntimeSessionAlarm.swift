//
//  WKExtendedRuntimeSessionAlarm.swift
//  BlinkBreak Watch App
//
//  Concrete implementation of SessionAlarmProtocol backed by WKExtendedRuntimeSession.
//  Holds the Watch app alive in the background for the duration of one 20-minute cycle,
//  then at break time calls session.notifyUser(hapticType:repeatHandler:) to play a
//  repeating haptic until the user taps Start break (which calls disarm) or the ~30s
//  maximum elapses.
//
//  Also posts a Watch-local notification at break time so the user has a tappable
//  notification-center entry with the "Start break" action visible directly from the
//  wrist (the thing that was broken in V1).
//
//  Not unit-tested — this class is a thin translator between the protocol and the
//  platform APIs. Interesting logic lives in SessionController and is covered via
//  MockSessionAlarm. Manual on-device verification is the test plan.
//

import Foundation
import WatchKit
import UserNotifications
import BlinkBreakCore

/// Watch-side alarm that holds an extended runtime session alive and fires repeating
/// haptics + a local notification when the break fire date is reached.
final class WKExtendedRuntimeSessionAlarm: NSObject, SessionAlarmProtocol, @unchecked Sendable {

    // MARK: - State

    private let lock = NSLock()
    private var armedCycleId: UUID?
    private var session: WKExtendedRuntimeSession?
    private var fireTimer: DispatchSourceTimer?
    private var disarmed: Bool = false
    private var hapticStartTime: Date?

    /// Maximum elapsed time the haptic loop continues before auto-terminating.
    /// Matches the cascade's original ~25–30 second alarm window.
    private let maxHapticSeconds: TimeInterval = 30

    // MARK: - SessionAlarmProtocol

    func arm(cycleId: UUID, fireDate: Date) {
        // Defensive: if we already have an armed cycle, tear it down first.
        disarmInternal()

        lock.lock()
        armedCycleId = cycleId
        disarmed = false
        lock.unlock()

        // Start the extended runtime session. This keeps the Watch app alive in the
        // background for this cycle. Session type .selfCare covers self-care activities
        // like the 20-20-20 eye rest.
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        session = newSession

        // Schedule a DispatchSourceTimer for the break fire date. When it fires, we
        // kick off the repeating haptic + post the Watch-local notification.
        let delay = max(fireDate.timeIntervalSinceNow, 0.1)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.fireAlarm(cycleId: cycleId)
        }
        timer.resume()
        fireTimer = timer
    }

    func disarm(cycleId: UUID) {
        lock.lock()
        guard armedCycleId == cycleId else {
            lock.unlock()
            return
        }
        lock.unlock()
        disarmInternal()
        removeDeliveredNotification(for: cycleId)
    }

    // MARK: - Private

    private func disarmInternal() {
        lock.lock()
        disarmed = true
        armedCycleId = nil
        lock.unlock()

        fireTimer?.cancel()
        fireTimer = nil

        if let s = session, s.state == .running {
            s.invalidate()
        }
        session = nil
    }

    private func fireAlarm(cycleId: UUID) {
        guard let s = session, s.state == .running else { return }

        lock.lock()
        hapticStartTime = Date()
        lock.unlock()

        // Kick off the repeating haptic. The repeat handler is called by the system
        // after each haptic. It receives an UnsafeMutablePointer<WKHapticType> to which
        // it can write the *next* haptic type to play, and returns the interval (in
        // seconds) until the next invocation — returning 0 terminates the loop.
        //
        // We track elapsed time ourselves (start time captured above) because the handler
        // doesn't receive it as a parameter.
        s.notifyUser(hapticType: .notification) { [weak self] nextHapticTypePointer in
            guard let self else {
                return 0
            }

            // Keep using the same haptic type for every repeat.
            nextHapticTypePointer.pointee = .notification

            self.lock.lock()
            let isDisarmed = self.disarmed
            let started = self.hapticStartTime
            self.lock.unlock()

            let elapsed = started.map { Date().timeIntervalSince($0) } ?? 0

            if isDisarmed || elapsed >= self.maxHapticSeconds {
                // Invalidate the session on the main queue so no further invocations
                // can happen even if the 0-return isn't respected.
                DispatchQueue.main.async { [weak self] in
                    if let s = self?.session, s.state == .running {
                        s.invalidate()
                    }
                }
                return 0
            }

            return 1.0
        }

        postWatchLocalNotification(cycleId: cycleId)
    }

    private func postWatchLocalNotification(cycleId: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Time to look away"
        content.body = "Focus on something 20 feet away for 20 seconds."
        content.sound = .default
        content.categoryIdentifier = BlinkBreakConstants.breakCategoryId
        content.threadIdentifier = cycleId.uuidString
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WKExtendedRuntimeSessionAlarm] notification add failed: \(error)")
            }
        }
    }

    private func removeDeliveredNotification(for cycleId: UUID) {
        let id = BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WKExtendedRuntimeSessionAlarm: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[WKExtendedRuntimeSessionAlarm] session started")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Session is about to be reclaimed. We don't attempt renewal — the iPhone
        // notification at T+20:00 is the fallback that guarantees the user still
        // gets alerted even if the session dies early.
        print("[WKExtendedRuntimeSessionAlarm] session will expire — relying on iPhone fallback")
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        print("[WKExtendedRuntimeSessionAlarm] session invalidated: reason=\(reason.rawValue) error=\(String(describing: error))")
        lock.lock()
        session = nil
        lock.unlock()
    }
}
