//
//  SessionAlarm.swift
//  BlinkBreakCore
//
//  Protocol abstraction for "hold an extended runtime session and fire a repeating
//  haptic at a specific time, until acknowledged." Zero WatchKit imports — the
//  protocol lives in the core package; the concrete WKExtendedRuntimeSession-backed
//  implementation lives in the Watch app target.
//
//  SessionController depends on this protocol; iPhone injects NoopSessionAlarm
//  (iPhone doesn't hold the extended runtime session), Watch injects
//  WKExtendedRuntimeSessionAlarm (lives in BlinkBreak Watch App/), tests inject
//  MockSessionAlarm.
//
//  Flutter analogue: an abstract PlatformAlarmService with a NoopPlatformAlarm
//  and a WatchOSPlatformAlarm implementation in platform-specific directories.
//

import Foundation

/// Abstracts "at time `fireDate`, play a repeating haptic pattern until acknowledged."
/// Implementations are responsible for holding whatever runtime-session machinery they
/// need alive in the background. `arm` and `disarm` must both be idempotent.
public protocol SessionAlarmProtocol: Sendable {

    /// Called when a new cycle begins (either via `start()` or after a break ack).
    /// The implementation should prepare its alarm machinery to fire at `fireDate`
    /// and play a repeating haptic until `disarm(cycleId:)` is called for the matching
    /// cycleId or an implementation-internal maximum duration (~30 seconds) is reached.
    ///
    /// Calling `arm` when another cycle is already armed must first disarm the previous
    /// cycle (there can only ever be one armed cycle at a time).
    func arm(cycleId: UUID, fireDate: Date)

    /// Called when the user acknowledges a break (on either device) or stops the session.
    /// Must be idempotent: calling `disarm` for a cycleId that isn't armed is a no-op.
    /// Disarming must stop any in-progress haptic loop on the next haptic invocation.
    func disarm(cycleId: UUID)
}

/// A `SessionAlarmProtocol` that does nothing. Used on iPhone (where the extended
/// runtime session isn't available / isn't needed — iPhone uses a notification with
/// a custom sound as its alarm) and in tests that don't care about the alarm path.
public final class NoopSessionAlarm: SessionAlarmProtocol, @unchecked Sendable {

    public init() {}

    public func arm(cycleId: UUID, fireDate: Date) {}

    public func disarm(cycleId: UUID) {}
}
