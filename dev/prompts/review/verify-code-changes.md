# Verify Code Changes

Verify that a code change accomplishes its intent. Review only; do not edit
the code under review.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read [AGENTS.md](../../../AGENTS.md), and do not report the intentional
   decisions it describes.

## Safety

Before running any command, read these sections of
[AGENTS.md](../../../AGENTS.md) and follow them strictly; they override
anything in this prompt:

- "Safety: the Recorder and the Real History File": above all, never start
  a recorder (run the viewer only with `--once`, or with `--no-record`
  under `timeout`), and give every run but `--help` and `--version` a
  scratch history file.
- "Safety: the Host and the Repository": never install anything, change git
  state or config, or release.

## Inputs

- **Comparison point:** anything `git diff` accepts (a commit such as `HEAD~2`
  or a SHA, a branch, or a tag). If none is given, ask for it before doing
  anything else.
- **Intent:** what the change is meant to do (feature, bug fix, tests,
  documentation). If none is given, infer it from the commit messages in the
  range, and say at the top of the report that you did so.

Review `git --no-pager diff <comparison-point>`, which includes uncommitted
changes to tracked files. `git diff` does not show new untracked files, so also
run `git status --short` and read any untracked files that belong to the
change. Say in the report whether uncommitted work was included.

## Evaluate

Assess whether the change is:

- **Correct:** it does what the intent says, including edge cases and error
  paths, in every mode it affects (the panel, `--lines`, `--once`, the
  recorder).
- **Complete:** nothing needed is missing (callers, the README, the
  CHANGELOG, `--help` output).
- **Simple and concise:** no unnecessary code, and no hand-written logic that
  an existing helper or the standard library provides. The gem has no
  runtime dependencies and must stay that way.
- **Compatible:** it runs on Ruby 2.6 (no newer syntax or standard-library
  APIs).
- **Idiomatic:** it follows the project's conventions and Ruby best practices.
- **Tested:** specs cover the new behavior and its failure modes. On Ruby 3.2
  or later, `bundle exec rspec` writes `coverage/coverage.json`; check the
  changed files' coverage with cov-loupe if it's available.

Where feasible, run `bundle exec rubocop` and the relevant specs, and say what
you ran. A partial `bundle exec rspec` run rewrites `coverage/coverage.json`:
every file in `lib/` (but `version.rb`, which coverage skips) is still listed, but files the run didn't exercise show
little or no coverage. So end with a full run.

Include only findings that would change what the author does. Omit remarks
such as "approach X could have been used, but the current one is a better
fit."

## Output

Write the report as Markdown to `untracked/` (create it if needed), named:

`<UTC timestamp %Y-%m-%d-%H-%M>-code-review-<agent>-<intent-slug>.md`

where `<agent>` is your lowercase tool name (e.g. `claude`, `codex`, `gemini`)
and `<intent-slug>` is a few hyphenated words describing the intent.
Example: `2026-01-08-19-45-code-review-claude-add-utc-option.md`.

Open with a one-line verdict, then the findings ordered by severity, each with
`path:line`, the problem, and a suggested fix. Also give the report in your
final message, for runners (such as agent-council) that collect it there.
