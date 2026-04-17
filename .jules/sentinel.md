## 2025-02-18 - [Fix Markdown Injection in BugReporter]
**Vulnerability:** The `userDescription` field submitted in the bug report inside `GitHubIssueReporter` was not sanitized before being injected into a markdown template.
**Learning:** Input submitted by users via a frontend can contain harmful payloads (like HTML/Markdown injections) that can break formats or perform XSS if viewed on GitHub issues.
**Prevention:** Ensure that all user inputs inserted into structured formats (like Markdown, HTML, JSON) are properly escaped or sanitized (e.g., replacing `<` with `&lt;`).
