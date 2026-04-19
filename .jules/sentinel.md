## 2025-02-18 - [Fix Markdown Injection in BugReporter]
**Vulnerability:** The `userDescription` field submitted in the bug report inside `GitHubIssueReporter` was not sanitized before being injected into a markdown template.
**Learning:** Input submitted by users via a frontend can contain harmful payloads (like HTML/Markdown injections) that can break formats or perform XSS if viewed on GitHub issues.
**Prevention:** Ensure that all user inputs inserted into structured formats (like Markdown, HTML, JSON) are properly escaped or sanitized (e.g., replacing `<` with `&lt;`).

## 2024-05-24 - [Add timeout and input limits to external network dependencies]
**Vulnerability:** Found `GitHubIssueReporter.swift` lacked an explicit timeout in its `URLRequest` and accepted an unconstrained `userDescription` string for the bug report body. This could lead to hanging connections (resource exhaustion) and large payload DoS when communicating with the GitHub API.
**Learning:** Network dependencies in this codebase must always explicitly set `timeoutInterval` and bound user input length to prevent denial-of-service vectors, even if the feature is scoped to TestFlight users.
**Prevention:** Always configure an explicit `.timeoutInterval` on `URLRequest` instances and use `.prefix()` to truncate arbitrary user input strings before serializing them into network payloads.

## 2024-05-25 - [Sanitize and Bound Log Buffer Contents]
**Vulnerability:** The LogBuffer accepted unbounded log messages, and the BugReporter did not sanitize triple backticks (` ``` `) from log entry messages before embedding them in the Markdown body of the GitHub issue.
**Learning:** This combination could lead to Memory Exhaustion (DoS via large log sizes keeping them in memory) and Markdown Injection (where an unescaped triple backtick breaks out of the intended details `<details>` code block).
**Prevention:** Bound unbounded strings (using `.prefix(1000)`) before retaining them in memory, and specifically sanitize inputs before placing them into formatted contexts (like Markdown code blocks or HTML).
