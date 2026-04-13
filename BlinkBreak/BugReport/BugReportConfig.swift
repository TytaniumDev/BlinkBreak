//
//  BugReportConfig.swift
//  BlinkBreak
//
//  Configuration for the bug report feature. The PAT is read from Info.plist at
//  runtime, injected via a build setting so the token never lives in source code.
//
//  To set up:
//  1. Go to https://github.com/settings/tokens?type=beta
//  2. Create a fine-grained PAT with:
//     - Repository access: TytaniumDev/BlinkBreak only
//     - Permissions: Issues -> Read and write
//  3. Set the BUG_REPORT_GITHUB_TOKEN build setting — either:
//     a. In a local .xcconfig file (gitignored), or
//     b. As a CI secret in the deploy-testflight workflow
//  4. Create the "bug-report" label on the repo if it doesn't exist.
//

import Foundation

enum BugReportConfig {
    /// Fine-grained GitHub PAT, read from Info.plist at runtime.
    /// The Info.plist key `BugReportGitHubToken` is set to `$(BUG_REPORT_GITHUB_TOKEN)`
    /// in project.yml. If the build setting is undefined, the literal string
    /// `$(BUG_REPORT_GITHUB_TOKEN)` is stored and we treat it as missing.
    static var gitHubToken: String? {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "BugReportGitHubToken") as? String,
              !token.isEmpty,
              !token.hasPrefix("$(") else {
            return nil
        }
        return token
    }

    /// The target repository for bug report issues.
    static let gitHubRepo = "TytaniumDev/BlinkBreak"
}
