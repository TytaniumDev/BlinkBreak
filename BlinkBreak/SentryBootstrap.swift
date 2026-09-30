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

import BlinkBreakCore
import Foundation
import Sentry

enum SentryBootstrap {

    private static let dsn = "https://fd928e6484dcf31e36e47fbfa3ee22d3@o4510951154712576.ingest.us.sentry.io/4511259403747328"

    /// Starts Sentry. Called once, from `BlinkBreakApp.init()`. No-op in DEBUG.
    static func start() {
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = releaseName
            options.environment = "production"
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true
            // Crashes + errors only. No performance traces (keeps us well
            // inside the free tier and avoids paying for spans we don't use).
            options.tracesSampleRate = 0.0
        }

        Task {
            if await DistributionChannel.isTestFlight() {
                SentrySDK.configureScope { $0.setEnvironment("testflight") }
            }
        }

        // Mirror log messages into breadcrumbs as they happen, so a crash report
        // carries the recent history (Sentry persists breadcrumbs with the crash).
        AppLogger.shared.setSink { level, message in
            let crumb = Breadcrumb()
            crumb.level = sentryLevel(for: level)
            crumb.category = "blinkbreak"
            crumb.message = message
            SentrySDK.addBreadcrumb(crumb)
        }
        #endif
    }

    private static var releaseName: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let bundle = Bundle.main.bundleIdentifier ?? "com.tytaniumdev.BlinkBreak"
        return "\(bundle)@\(version)+\(build)"
    }

    private static func sentryLevel(for level: LogLevel) -> SentryLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}
