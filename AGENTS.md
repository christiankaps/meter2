# Agent Instructions

## Core Principle

The app must always remain functional. Every implementation change must leave the project in a compilable, tested, reviewed, and committed state before the work is considered complete.

## Language

- User-facing app text must support German and English.
- Source code, code comments, tests, developer documentation, and Markdown files must be written in English.

## Clean Code

- Always check whether a change creates dead code, unused helpers, obsolete tests, unreachable branches, redundant assets, or stale documentation.
- Remove dead code as part of the same change when it is clearly related to the work.
- Keep changes small, direct, and easy to review.

## UX Principle

Act as a UX expert and prioritize simplicity.

- Every user action should have one clear, simple way to trigger it.
- Avoid multiple visible buttons or controls that do the same thing.
- Prefer one obvious primary action over duplicated toolbar, sidebar, context-menu, and inline actions.
- Keep UI flows calm, focused, and understandable without explanatory text where the interface itself can be made clearer.

## Model Usage And Token Economy

Save AI tokens by matching model strength to the task.

- Use a really powerful model only for planning, product decisions, architecture choices, complex debugging strategy, and other work where deeper reasoning materially improves the outcome.
- Use a lightweight fast model for implementation, code editing, straightforward execution tasks, builds, test runs, git operations, and fast reviews.
- Use a lightweight fast model for review tasks unless the review is explicitly the deeper analyzing review required by the workflow.
- Prefer concise prompts to subagents and include only the context they need for the assigned task.
- Do not use a more powerful model merely because a task is large; use it when the task is conceptually difficult, ambiguous, or high risk.

## Required Workflow For Code Changes

Use this workflow whenever source code, project configuration, build settings, tests, app resources, data models, app behavior, or any executable artifact is changed.

1. Implement the smallest safe change that satisfies the request.
2. Compile the app immediately after the change.
3. Continue only if compilation succeeds.
4. Determine the changed-line count for the final diff.
5. If the change is small, meaning fewer than 200 changed lines, skip the fast review and request one deeper analyzing subagent review focused on architecture, edge cases, data safety, UX simplicity, test coverage, and long-term maintainability.
6. If the change is 200 changed lines or larger, request a first review from a fast subagent focused on obvious regressions, build risks, missed requirements, and UX duplication.
7. Address any actionable findings from the fast review when one was required.
8. If any changes were made to address fast review findings, restart this workflow at the compile step.
9. For changes of 200 changed lines or larger, request a second review from a deeper analyzing subagent focused on architecture, edge cases, data safety, UX simplicity, test coverage, and long-term maintainability.
10. Address any actionable findings from the deeper review.
11. If any changes were made to address deeper review findings, restart this workflow at the compile step.
12. Run the complete test suite only after the required review stage or stages pass without requiring more changes.
13. Fix any failing tests or regressions.
14. If any changes were made to fix failing tests or regressions, restart this workflow at the compile step.
15. Create a commit with a clear English commit message.
16. Push the commit to the remote branch.

If any step fails, do not continue to later steps until the failure is understood and resolved.

## Build Requirement

After every code or app-behavior change, the app must be compiled. A change is not complete until the compile step succeeds.

The build command should use the current native macOS project configuration. If multiple build commands exist, prefer the one used by the repository's established workflow.

## Review Requirement

After a successful compile, every code change must be reviewed.

Reuse existing subagents for reviews when a suitable review subagent is already available in the current thread and can reasonably continue the review context.

Small changes, meaning fewer than 200 changed lines, require one deeper analyzing subagent review. Skip the fast review for these small changes.

Larger changes, meaning 200 changed lines or more, must be reviewed in two stages:

- Fast review: a quick subagent review for clear mistakes, regressions, and missing request coverage.
- Deep review: a more thorough subagent review for architecture, edge cases, data integrity, localization, privacy, maintainability, and test quality.

When both review stages are required, the deeper review must happen after the fast review findings have been considered.

## Review Fix Restart Requirement

Any code, project, resource, test, or executable-behavior change made to address review feedback invalidates the previous build, review, and test results. After such a fix, the next required step is a fresh compile.

For changes of 200 changed lines or larger, the complete verification sequence must then repeat:

```text
build -> fast review -> deep review -> full tests
```

For changes smaller than 200 changed lines, the complete verification sequence must then repeat:

```text
build -> deep review -> full tests
```

Pure discussion, clarification, or explicit dismissal of a non-actionable review finding does not restart the sequence unless it results in a code, project, resource, test, or executable-behavior change.

## Test Requirement

After the required review stage or stages are complete and their actionable findings are addressed, run the full test suite.

Do not commit or push code changes while tests are failing unless the user explicitly asks for a work-in-progress commit and the commit message clearly states the known failing state.

## Commit And Push Requirement

After a code change has compiled, passed the required review stage or stages, and passed all tests:

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

## Release Creation

GitHub releases must use the repository release workflow as the only source for release builds and DMG assets.

- Never upload locally built apps, archives, ZIPs, or DMGs to a GitHub release.
- Do not create release assets manually from a local machine.
- To create a release, first ensure the version bump and release notes are committed and pushed.
- Create or publish the GitHub release without locally built assets, then let `.github/workflows/release.yml` build the app on GitHub Actions and attach the DMG.
- Do not watch GitHub workflow runs with long-running commands such as `gh run watch`.
- Check workflow status only with short, bounded status queries such as `gh run list` or `gh run view`, and repeat manually only when needed.
- After the workflow completes, verify that the release contains exactly one DMG generated by GitHub Actions.
- If a release accidentally contains a locally uploaded asset or duplicate DMGs, remove the local or duplicate asset before considering the release complete.

## Requirements And Lessons Learned

Maintain `docs/REQUIREMENTS.md` as the shared product requirements record.

- Add every requested, planned, deferred, or discovered feature to the requirements file.
- Mark each feature with its current status, such as `Planned`, `In Progress`, `Implemented`, `Deferred`, or `Rejected`.
- Keep implemented features documented with enough detail to understand the delivered behavior.
- Update the file whenever implementation choices change the planned scope or behavior.
- Maintain a `Lessons Learned` section for bugs, regressions, confusing behavior, or workflow issues that were discovered during development.
- For each lesson learned, document the problem, root cause when known, solution, and any follow-up prevention step such as a test, validation rule, or workflow change.
- Treat requirements-file updates as documentation-only unless the same change also touches code, project configuration, resources, tests, or executable behavior.

## Documentation-Only Exception

If no code is touched and the change is limited to documentation, planning notes, Markdown files, comments outside source code, or other non-executable text, the build, subagent review, test, commit, and push workflow may be skipped.

Documentation-only changes should still be checked for clarity, consistency, and spelling before completion.

## Safety Rules

- Never knowingly leave the app uncompilable after a code change.
- Never skip the compile step for code changes.
- Never skip the required review stage or stages for code changes unless the user explicitly overrides this instruction.
- Never skip tests after reviewed code changes unless the user explicitly overrides this instruction.
- Never commit unrelated files.
- Never push unreviewed or untested code changes unless the user explicitly asks for that risk.
