# Agent Instructions

## Core Principle

The app must always remain functional. Every implementation change must leave the project in a compilable, tested, reviewed, and committed state before the work is considered complete.

## Branching Policy

All work happens directly on the `main` branch.

- Do not create feature branches, topic branches, or temporary branches.
- Do not open pull requests; this repository does not use PR-based review.
- Commit completed, verified changes directly to `main` and push to `origin/main`.
- The quality gate is the local workflow below (build, subagent review, tests), not a branch or pull request.
- If local `main` is behind `origin/main`, rebase local commits onto `origin/main` before pushing; do not create merge commits from side branches.

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
- Always use a lightweight, cheaper model for required review tasks.
- Prefer concise prompts to subagents and include only the context they need for the assigned task.
- Reuse suitable existing subagents when they can reasonably continue the current review or verification context.
- Do not use a more powerful model merely because a task is large; use it when the task is conceptually difficult, ambiguous, or high risk.
- Do not use subagents for documentation-only, pure version-bump, release-note-only, command-only, or status-check tasks.
- For routine reviews, do not fork full thread context. Pass only the changed files, diff summary, relevant requirements, and exact review focus.

## Tool Output And Log Hygiene

Keep tool output bounded and high signal.

- Prefer summary commands over full logs.
- For build and test runs, inspect and report the final result plus actionable failures. Avoid relaying long successful `xcodebuild` logs.
- When long logs are needed for debugging, write or keep them in a temporary location and inspect targeted snippets.
- Do not paste large diffs, generated files, or full build logs into subagent prompts. Summarize and point to files instead.

## Required Workflow For Code Changes

Use this workflow whenever source code, project configuration, build settings, tests, app resources, data models, app behavior, or any executable artifact is changed.

Choose the lightest workflow that matches the change type:

| Change type | Required verification |
| --- | --- |
| Documentation-only, planning notes, comments outside source code, or other non-executable text | Check clarity and `git diff --check`; build, subagent review, and tests may be skipped. |
| Pure release version bump that only changes `MARKETING_VERSION` | Verify the diff only contains the expected version lines, run `make build`, run `make test`, then commit and push. Subagent review may be skipped unless the diff includes other project changes. |
| Release-note-only or GitHub release metadata changes | Verify release target, notes, and assets with bounded `gh` queries. Do not build locally or upload local assets. |
| Code or app-behavior change | Build, fast review with a lightweight cheaper model, full non-UI tests, commit, push. |

Default code-change sequence:

1. Implement the smallest safe change that satisfies the request.
2. Compile the app immediately after the change.
3. Continue only if compilation succeeds.
4. Request one fast subagent review using a lightweight cheaper model, focused on obvious regressions, build risks, missed requirements, UX duplication, edge cases, localization, data safety, and test coverage.
5. Address any actionable findings from the fast review.
6. If any changes were made to address fast review findings, restart this workflow at the compile step.
7. Run the complete non-UI test suite only after the required review stage passes without requiring more changes.
8. Fix any failing tests or regressions.
9. If any changes were made to fix failing tests or regressions, restart this workflow at the compile step.
10. Create a commit with a clear English commit message on `main`.
11. Push the commit directly to `origin/main`.

If any step fails, do not continue to later steps until the failure is understood and resolved.

Generated, mechanical, or formatting-heavy files such as `.xcstrings`, `.pbxproj`, regenerated assets, and lockfiles may inflate raw changed-line counts. Keep review prompts concise and focused on the semantic change while still reviewing generated output for obvious mistakes.

## Build Requirement

After every code or app-behavior change, the app must be compiled. A change is not complete until the compile step succeeds.

The build command should use the current native macOS project configuration. If multiple build commands exist, prefer the one used by the repository's established workflow.

## Review Requirement

After a successful compile, every normal code or app-behavior change must be reviewed.

Reuse existing subagents for reviews when a suitable review subagent is already available in the current thread and can reasonably continue the review context.

Every normal code change requires one fast subagent review using a lightweight cheaper model. The review should focus on clear mistakes, regressions, missing request coverage, UX duplication, edge cases, localization, data integrity, privacy, maintainability, and test quality.

If subagent review is unavailable because of platform limits, tool errors, or quota exhaustion, perform a local checklist review instead, document that limitation in the final response, and continue only after build and tests pass.

## Review Fix Restart Requirement

Any code, project, resource, test, or executable-behavior change made to address review feedback invalidates the previous build, review, and test results. After such a fix, the next required step is a fresh compile.

The complete verification sequence must then repeat:

```text
build -> fast review -> full non-UI tests
```

Pure discussion, clarification, or explicit dismissal of a non-actionable review finding does not restart the sequence unless it results in a code, project, resource, test, or executable-behavior change.

## Test Requirement

After the required review stage is complete and its actionable findings are addressed, run the full non-UI test suite.

UI tests are not part of this repository's required workflow. Do not create, maintain, run, or require UI test targets, UI test schemes, `make test-ui`, `make ui-test`, or equivalent Xcode UI test commands.

Do not commit or push code changes while tests are failing unless the user explicitly asks for a work-in-progress commit and the commit message clearly states the known failing state.

## Commit And Push Requirement

After a code change has compiled, passed the required review stage, and passed all required non-UI tests:

1. Stage only the files that belong to the completed change.
2. Create a focused commit with an English commit message on `main`.
3. Push the commit directly to `origin/main`.

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
- Do not run `make release-build` for normal release creation. Use it only when explicitly debugging the release build.
- To create a release, first ensure the version bump and release notes are committed and pushed.
- Create or publish the GitHub release without assets, then let `.github/workflows/release.yml` build the app on GitHub Actions and attach the DMG.
- Do not watch GitHub workflow runs with long-running commands such as `gh run watch`.
- Check workflow status only with short, bounded status queries such as `gh run list` or `gh run view`, and repeat manually only when needed.
- After the workflow completes, verify that the release contains exactly one DMG generated by GitHub Actions.
- If a release accidentally contains a locally uploaded asset or duplicate DMGs, remove the local or duplicate asset before considering the release complete.

## Requirements And Lessons Learned

Maintain `docs/REQUIREMENTS.md` as the shared product requirements record.

- Add requested, planned, deferred, or discovered product features when they materially affect scope, commitments, delivered behavior, or known risks.
- Mark each feature with its current status, such as `Planned`, `In Progress`, `Implemented`, `Deferred`, or `Rejected`.
- Keep implemented features documented with enough detail to understand the delivered behavior.
- Update the file whenever implementation choices materially change the planned scope or behavior.
- Maintain a `Lessons Learned` section for bugs, regressions, confusing behavior, or workflow issues that were discovered during development.
- For each material lesson learned, document the problem, root cause when known, solution, and any follow-up prevention step such as a test, validation rule, or workflow change.
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
