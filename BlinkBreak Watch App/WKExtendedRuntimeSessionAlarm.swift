//
//  WKExtendedRuntimeSessionAlarm.swift
//  BlinkBreak Watch App
//
//  Concrete SessionAlarmProtocol backed by a `.smartAlarm` WKExtendedRuntimeSession.
//
//  Why smart-alarm (not self-care): self-care sessions cap at ~10 minutes from
//  session start, which is shorter than our 20-minute break interval — the
//  session dies before break time so the haptic loop never runs. smart-alarm
//  supports `session.start(at:)` instead: the runtime clock doesn't begin until
//  the scheduled fire date, and when it fires we get ~30 seconds to play a
//  repeating haptic via `notifyUser(hapticType:repeatHandler:)`.
//
//  Flow:
//  1. `arm(cycleId:fireDate:)` calls `session.start(at: fireDate)` and schedules
//     a Watch-local notification with the same fireDate (as a fallback, and to
//     carry the "Start break" action button visible in Notification Center).
//  2. At fireDate, watchOS starts the session and calls
//     `extendedRuntimeSessionDidStart` on the delegate. That callback kicks off
//     the repeating haptic loop via `notifyUser(hapticType:repeatHandler:)`.
//  3. The repeat handler runs until the user acknowledges (disarm() called) or
//     ~30 seconds elapse, whichever comes first.
//
//  Not unit-tested — this class is a thin translator between the protocol and
//  the platform APIs. Manual on-device verification covers it.
//

import Foundation
import WatchKit
import UserNotifications
import BlinkBreakCore

final class WKExtendedRuntimeSessionAlarm: NSObject, SessionAlarmProtocol, @unchecked Sendable {

    // MARK: - State

    private let lock = NSLock()
    private var armedCycleId: UUID?
    private var session: WKExtendedRuntimeSession?
    private var disarmed: Bool = false
    private var hapticStartTime: Date?

    /// Maximum time the haptic loop runs before auto-terminating. Apple's smart-alarm
    /// session budget is ~30 seconds of runtime after the session fires, so this
    /// also matches the platform cap.
    private let maxHapticSeconds: TimeInterval = 30

    // MARK: - SessionAlarmProtocol

    func arm(cycleId: UUID, fireDate: Date) {
        // Tear down any previously-armed cycle first.
        disarmInternal()

        // Schedule the session to start AT the break fire date. Smart-alarm runtime
        // doesn't begin consuming until the session fires, so we're not bound by
        // the ~10-minute cap that killed the previous .selfCare approach. Guard
        // against past/near-zero offsets — Apple doesn't document `start(at:)`'s
        // behavior with a non-future date; nudging forward 0.1s mirrors the
        // notification-trigger guard below.
        let startDate = max(fireDate, Date(timeIntervalSinceNow: 0.1))
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start(at: startDate)

        lock.lock()
        armedCycleId = cycleId
        disarmed = false
        session = newSession
        lock.unlock()

        // Schedule a Watch-local notification at the same fireDate. Two purposes:
        //  1. Fallback: if the session fails to fire (e.g., app wasn't foreground-
        //     reachable when arm() ran from a background wake), the notification
        //     still delivers a `.timeSensitive` alert.
        //  2. UI surface: the notification carries the "Start break" action button
        //     visible from the lock screen / Notification Center — haptics alone
        //     don't give the user a way to acknowledge without opening the app.
        scheduleWatchLocalNotification(cycleId: cycleId, fireDate: fireDate)
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
        // Extract the session under the lock, then invalidate outside the lock.
        // `invalidate()` is safe on any session state (a no-op on already-
        // invalidated sessions) and cancels both pending `.scheduled` and active
        // `.running` sessions, so no state branching is needed.
        lock.lock()
        disarmed = true
        armedCycleId = nil
        hapticStartTime = nil
        let sessionToInvalidate = session
        session = nil
        lock.unlock()

        sessionToInvalidate?.invalidate()
    }

    /// Schedule a Watch-local notification with a system-managed trigger so it fires
    /// even if the scheduled session fails for any reason.
    private func scheduleWatchLocalNotification(cycleId: UUID, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Time to look away"
        content.body = "Tap to start your 20-second break."
        content.sound = .default
        content.categoryIdentifier = BlinkBreakConstants.breakCategoryId
        content.threadIdentifier = cycleId.uuidString
        content.interruptionLevel = .timeSensitive

        let delay = max(fireDate.timeIntervalSinceNow, 0.1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WKExtendedRuntimeSessionAlarm] notification schedule failed: \(error)")
            }
        }
    }

    private func removeDeliveredNotification(for cycleId: UUID) {
        let id = BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Start the repeating haptic loop on the given session. Called from
    /// `extendedRuntimeSessionDidStart` when the smart-alarm fires at break time.
    private func playHapticLoop(on session: WKExtendedRuntimeSession) {
        lock.lock()
        hapticStartTime = Date()
        lock.unlock()

        // `notifyUser` invokes the closure after each haptic, writes the NEXT haptic
        // type to play through the pointer, and returns the delay (seconds) until
        // the next invocation. Returning 0 stops the loop. We track elapsed time
        // ourselves via `hapticStartTime` since the closure doesn't receive it.
        //
        // Capture `session` weakly instead of reading `self.session` — the repeat
        // handler runs off the main queue, and `self.session` is locked state that
        // might have been cleared by a concurrent disarm.
        session.notifyUser(hapticType: .notification) { [weak self, weak session] nextHapticTypePointer in
            guard let self, let session else { return 0 }

            nextHapticTypePointer.pointee = .notification

            self.lock.lock()
            let isDisarmed = self.disarmed
            let started = self.hapticStartTime
            self.lock.unlock()

            let elapsed = started.map { Date().timeIntervalSince($0) } ?? 0

            if isDisarmed || elapsed >= self.maxHapticSeconds {
                DispatchQueue.main.async {
                    session.invalidate()
                }
                return 0
            }
            return 1.0
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WKExtendedRuntimeSessionAlarm: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // The smart-alarm fire date has arrived and the session is now running.
        // Guarded by `disarmed` so a late-arriving session-did-start (e.g. user
        // already acknowledged the break before the session fired) doesn't buzz
        // the wrist for a break the user already handled.
        lock.lock()
        let isDisarmed = disarmed
        let expectedSession = session
        lock.unlock()

        guard !isDisarmed, extendedRuntimeSession === expectedSession else {
            extendedRuntimeSession.invalidate()
            return
        }

        playHapticLoop(on: extendedRuntimeSession)
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Smart-alarm sessions get ~30 seconds; this fires shortly before that cap.
        // Nothing to do — the haptic loop already self-terminates via the elapsed-
        // time check in its repeat handler, and the Watch-local notification that
        // accompanies the alarm handles the "user wasn't looking" case.
        #if DEBUG
        print("[WKExtendedRuntimeSessionAlarm] session will expire")
        #endif
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        #if DEBUG
        print("[WKExtendedRuntimeSessionAlarm] session invalidated: reason=\(reason.rawValue) error=\(String(describing: error))")
        #endif
        lock.lock()
        if session === extendedRuntimeSession {
            session = nil
        }
        lock.unlock()
    }
}
