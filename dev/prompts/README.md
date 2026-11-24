# Prompts for AI Agents

Prompts for AI coding agents working on claude-limit-watch, adapted from
cov-loupe's. Each one is meant to be given to an agent on its own (for
example, "Follow dev/prompts/review/release-review.md"), or run by
agent-council.

Every prompt here that runs commands, except the generic
review-latest-commit prompt, has the agent read and follow the two safety
sections of [AGENTS.md](../../AGENTS.md) first: never start a recorder or
touch the real history file, and never install anything, change git state,
or release. Review and validate prompts change no tracked files and give
their report in the agent's final message (Verify Code Changes and State of
the Code Base also save it to `untracked/`, which is gitignored). The
improve prompt edits documentation, then proposes a commit for the user to
run.

## Review

- [Review Latest Commit (safe)](review/review-latest-commit-safe-prompt.md):
  the latest commit and uncommitted changes. Use this one, not the generic
  [review-latest-commit-prompt.md](review/review-latest-commit-prompt.md),
  which lacks this project's safety rules.
- [Verify Code Changes](review/verify-code-changes.md): whether a change
  since a given commit does what it's meant to. "Did I do this right?"
- [Review Documentation](review/review-documentation.md): inaccurate,
  unclear, missing, or inconsistent docs, without changing them.
- [Release Review](review/release-review.md): a checklist of what's left
  before a release, alongside [docs/dev/RELEASING.md](../../docs/dev/RELEASING.md).
- [State of the Code Base](review/state-of-the-code-base-prompt.md): a
  periodic, scored assessment of the whole code base.

## Improve

- [Update Documentation](improve/update-documentation.md): fix the docs in
  place, and propose a commit.

## Validate

- [Test Documentation Examples](validate/test-documentation-examples.md):
  run the docs' examples (in safe forms) and report any that fail.
