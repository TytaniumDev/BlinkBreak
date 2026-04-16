## 2025-02-18 - [Fix Markdown Injection in BugReporter]
**Vulnerability:** The `userDescription` field submitted in the bug report inside `GitHubIssueReporter` was not sanitized before being injected into a markdown template.
**Learning:** Input submitted by users via a frontend can contain harmful payloads (like HTML/Markdown injections) that can break formats or perform XSS if viewed on GitHub issues.
**Prevention:** Ensure that all user inputs inserted into structured formats (like Markdown, HTML, JSON) are properly escaped or sanitized (e.g., replacing `<` with `&lt;`).

## 2024-05-24 - [Add timeout and input limits to external network dependencies]
**Vulnerability:** Found `GitHubIssueReporter.swift` lacked an explicit timeout in its `URLRequest` and accepted an unconstrained `userDescription` string for the bug report body. This could lead to hanging connections (resource exhaustion) and large payload DoS when communicating with the GitHub API.
**Learning:** Network dependencies in this codebase must always explicitly set `timeoutInterval` and bound user input length to prevent denial-of-service vectors, even if the feature is scoped to TestFlight users.
**Prevention:** Always configure an explicit `.timeoutInterval` on `URLRequest` instances and use `.prefix()` to truncate arbitrary user input strings before serializing them into network payloads.
