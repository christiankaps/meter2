# Agent Instructions

## Core Principle

The app must always remain functional. Every implementation change must leave the project in a compilable, tested, reviewed, and committed state before the work is considered complete.

## Language

- User-facing app text must support German and English.
- Source code, code comments, tests, developer documentation, and Markdown files must be written in English.

## Required Workflow For Code Changes

Use this workflow whenever source code, project configuration, build settings, tests, app resources, data models, app behavior, or any executable artifact is changed.

1. Implement the smallest safe change that satisfies the request.
2. Compile the app immediately after the change.
3. Continue only if compilation succeeds.
4. Request a first review from a fast subagent focused on obvious regressions, build risks, and missed requirements.
5. Address any actionable findings from the fast review.
6. Request a second review from a deeper analyzing subagent focused on architecture, edge cases, data safety, test coverage, and long-term maintainability.
7. Address any actionable findings from the deeper review.
8. Run the complete test suite.
9. Fix any failing tests or regressions.
10. Create a commit with a clear English commit message.
11. Push the commit to the remote branch.

If any step fails, do not continue to later steps until the failure is understood and resolved.

## Build Requirement

After every code or app-behavior change, the app must be compiled. A change is not complete until the compile step succeeds.

The build command should use the current native macOS project configuration. If multiple build commands exist, prefer the one used by the repository's established workflow.

## Review Requirement

After a successful compile, every code change must be reviewed in two stages:

- Fast review: a quick subagent review for clear mistakes, regressions, and missing request coverage.
- Deep review: a more thorough subagent review for architecture, edge cases, data integrity, localization, privacy, maintainability, and test quality.

The deeper review must happen after the fast review findings have been considered.

## Test Requirement

After both review stages are complete and their actionable findings are addressed, run the full test suite.

Do not commit or push code changes while tests are failing unless the user explicitly asks for a work-in-progress commit and the commit message clearly states the known failing state.

## Commit And Push Requirement

After a code change has compiled, passed both review stages, and passed all tests:

1. Stage only the files that belong to the completed change.
2. Create a focused commit with an English commit message.
3. Push the commit to the remote branch.

Do not include unrelated local changes in the commit.

## Versioning

Use the versioning schema:

```text
year.major.minor
```

Examples:

- `2026.1.0`
- `2026.1.1`
- `2026.2.0`

Version components:

- `year`: the calendar year of the release.
- `major`: increment for substantial features, larger user-facing changes, or meaningful product milestones within the year.
- `minor`: increment for fixes, small improvements, polish, and documentation updates that are released independently.

When the year changes, reset `major` and `minor` according to the first release planned for that year.

## Documentation-Only Exception

If no code is touched and the change is limited to documentation, planning notes, Markdown files, comments outside source code, or other non-executable text, the build, subagent review, test, commit, and push workflow may be skipped.

Documentation-only changes should still be checked for clarity, consistency, and spelling before completion.

## Safety Rules

- Never knowingly leave the app uncompilable after a code change.
- Never skip the compile step for code changes.
- Never skip the two-stage review for code changes unless the user explicitly overrides this instruction.
- Never skip tests after reviewed code changes unless the user explicitly overrides this instruction.
- Never commit unrelated files.
- Never push unreviewed or untested code changes unless the user explicitly asks for that risk.
