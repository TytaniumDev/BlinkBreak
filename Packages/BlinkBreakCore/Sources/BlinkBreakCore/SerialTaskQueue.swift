//
//  SerialTaskQueue.swift
//  BlinkBreakCore
//
//  Runs async operations one at a time, in the order they were submitted.
//
//  SessionController awaits AlarmKit in the middle of transitions. Without a
//  queue, a second transition (a Stop tap, an alarm event, a reconcile) could
//  start during that await and read half-updated state. With it, each
//  transition sees the finished result of the one before.
//
//  Flutter analogue: chaining every call onto one `Future` (`_last = _last.then(op)`).
//

import Foundation

@MainActor
final class SerialTaskQueue {

    private var tail: Task<Void, Never>?

    /// Queue `operation` behind everything submitted so far and return
    /// immediately. The operation must not submit to this queue and await it —
    /// that would wait on itself.
    @discardableResult
    func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        return task
    }

    /// Queue `operation` and wait for it to finish.
    func run(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        await enqueue(operation).value
    }

    /// Wait for everything submitted so far.
    func drain() async {
        await tail?.value
    }
}
