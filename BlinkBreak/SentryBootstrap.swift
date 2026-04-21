//
//  SentryBootstrap.swift
//  BlinkBreak
//
//  Initializes the Sentry SDK for crash / error reporting. Only active in Release
//  builds — DEBUG builds stay quiet so local development doesn't pollute the
//  production event stream.
//
//  The DSN is a public-facing credential (safe to commit; it's embedded in every
//  shipped app binary anyway). It identifies the project, not an auth secret.
//
//  dSYM uploads: handled by fastlane-plugin-sentry in the `beta` lane after each
//  TestFlight build. No Xcode build phase needed.
//

import Foundation
import BlinkBreakCore
import Sentry

enum SentryBootstrap {

    private static let dsn = "https://fd928e6484dcf31e36e47fbfa3ee22d3@o4510951154712576.ingest.us.sentry.io/4511259403747328"

    // Single-shot guard. `start()` is called from BlinkBreakApp.init() and should
    // only initialize the SDK once per process; extra calls are no-ops.
    private static let hasStarted = NSLock()
    nonisolated(unsafe) private static var didStart = false

    /// Starts Sentry. Safe to call more than once; subsequent calls are no-ops.
    /// No-op in DEBUG builds.
    static func start() {
        #if DEBUG
        return
        #else
        hasStarted.lock()
        if didStart {
            hasStarted.unlock()
            return
        }
        didStart = true
        hasStarted.unlock()

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Self.releaseName
            options.environment = Self.environment
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true
            // Crashes + errors only. No performance traces (keeps us well
            // inside the free tier and avoids paying for spans we don't use).
            options.tracesSampleRate = 0.0
            options.profilesSampleRate = 0.0
        }

        // Mirror log entries into Sentry as breadcrumbs in real time. This is
        // required for hard crashes: `beforeSend` runs on the NEXT launch after
        // a crash, by which point LogBuffer is empty. Sentry persists
        // breadcrumbs to disk with the crash report, so adding them at log-time
        // is what actually gets them into the crash payload.
        LogBuffer.shared.setObserver { entry in
            let crumb = Breadcrumb()
            crumb.timestamp = entry.timestamp
            crumb.level = Self.sentryLevel(for: entry.level)
            crumb.category = "blinkbreak"
            crumb.message = entry.message
            SentrySDK.addBreadcrumb(crumb)
        }
        #endif
    }

    private static var releaseName: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundle = Bundle.main.bundleIdentifier ?? "com.tytaniumdev.BlinkBreak"
        return "\(bundle)@\(version)+\(build)"
    }

    private static var environment: String {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "production"
    }

    private static func sentryLevel(for level: LogLevel) -> SentryLevel {
        switch level {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .warning
        case .error:   return .error
        }
    }
}
