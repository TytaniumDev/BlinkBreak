//
//  MeetingSkip.swift
//  BlinkBreakCore
//
//  Pure math for skipping breaks that land in a meeting while keeping the
//  20-minute rhythm: a break due at T moves to T + k × interval, the first such
//  slot that isn't inside any meeting.
//
//  Flutter analogue: a top-level pure function in its own file, unit-tested on
//  its own.
//

import Foundation

enum MeetingSkip {

    /// The first of `fireDate`, `fireDate + interval`, `fireDate + 2 × interval`, …
    /// that isn't inside a meeting. A slot exactly at a meeting's end is free.
    static func firstFreeSlot(
        from fireDate: Date,
        interval: TimeInterval,
        meetings: [DateInterval]
    ) -> Date {
        precondition(interval > 0)
        var slot = fireDate
        // Each pass jumps past at least one meeting's end, so this terminates.
        while let meeting = meetings.first(where: { $0.start <= slot && slot < $0.end }) {
            let skipped = (meeting.end.timeIntervalSince(slot) / interval).rounded(.up)
            slot = slot.addingTimeInterval(max(1, skipped) * interval)
        }
        return slot
    }
}
