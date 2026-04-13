//
//  BugReportConfig.swift
//  BlinkBreak
//
//  Configuration for the bug report feature. The PAT is a fine-grained GitHub token
//  scoped to issues:write on TytaniumDev/BlinkBreak only. This is acceptable for
//  TestFlight builds where all users are trusted testers.
//
//  To set up:
//  1. Go to https://github.com/settings/tokens?type=beta
//  2. Create a fine-grained PAT with:
//     - Repository access: TytaniumDev/BlinkBreak only
//     - Permissions: Issues -> Read and write
//  3. Paste the token below.
//  4. Create the "bug-report" label on the repo if it doesn't exist.
//

enum BugReportConfig {
    /// Fine-grained GitHub PAT scoped to issues:write on TytaniumDev/BlinkBreak.
    /// Replace this placeholder with a real token before building for TestFlight.
    static let gitHubToken = "REPLACE_WITH_GITHUB_PAT"

    /// The target repository for bug report issues.
    static let gitHubRepo = "TytaniumDev/BlinkBreak"
}
