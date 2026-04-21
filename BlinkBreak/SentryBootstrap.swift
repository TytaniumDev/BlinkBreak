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
//  dSYM uploads: enable the App Store Connect integration in Sentry project
//  settings (Settings → Integrations → App Store Connect). That auto-fetches
//  dSYMs from Apple after each TestFlight / App Store upload, which avoids
//  needing a sentry-cli build phase.
//

import Foundation
import BlinkBreakCore
import Sentry

enum SentryBootstrap {

    private static let dsn = "https://fd928e6484dcf31e36e47fbfa3ee22d3@o4510951154712576.ingest.us.sentry.io/4511259403747328"

    /// Starts Sentry. Safe to call more than once; subsequent calls are no-ops.
    /// No-op in DEBUG builds.
    static func start() {
        #if DEBUG
        return
        #else
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
            options.beforeSend = { event in
                // Attach the in-memory log ring buffer to every event as
                // breadcrumbs. Gives us the last ~500 diagnostic lines leading
                // up to the crash or error.
                let entries = LogBuffer.shared.drain()
                var breadcrumbs = event.breadcrumbs ?? []
                for entry in entries.suffix(100) {
                    let crumb = Breadcrumb()
                    crumb.timestamp = entry.timestamp
                    crumb.level = Self.sentryLevel(for: entry.level)
                    crumb.category = "blinkbreak"
                    crumb.message = entry.message
                    breadcrumbs.append(crumb)
                }
                event.breadcrumbs = breadcrumbs
                return event
            }
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
