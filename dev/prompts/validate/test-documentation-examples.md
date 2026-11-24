# Test Documentation Examples

**Purpose:** Verify that the command examples in the documentation run as
written and produce the documented output. Report only; do not edit files.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read [AGENTS.md](../../../AGENTS.md), especially "Safety: the Recorder
   and the Real History File" and "Manual Testing".

---

## When to Use This

- After documentation changes
- Before releases
- After changes to commands, options, or output that might affect examples

## Scope

Test the examples in `README.md`, `CONTRIBUTING.md`, and `docs/**/*.md`.
Don't test `CHANGELOG.md`, which describes past releases.

## Safety

Many of the README's examples are for users and, run as written, would start
a recorder, use the real history file, or stop the user's running recorder.

Before running any command, read these sections of
[AGENTS.md](../../../AGENTS.md) and follow them strictly; they override
anything in this prompt:

- "Safety: the Recorder and the Real History File": above all, never start
  a recorder (run the viewer only with `--once`, or with `--no-record`
  under `timeout`), and give every run but `--help` and `--version` a
  scratch history file.
- "Safety: the Host and the Repository": never install anything, change git
  state or config, or release.

So run each example only in a safe form:

- **Use the demo history** (below) as the history file: add
  `--file "$demo"` to every `exe/claude-limit-watch` run but `--help` and
  `--version`, and use `bundle exec exe/claude-limit-watch` in place of
  `claude-limit-watch`. (An empty history file shows only "no readings",
  which would make good examples look broken.)
- **Run the viewer only with `--once`, or with `--no-record` under
  `timeout`.** Examples of the plain viewer or `--lines`, including ones
  whose output goes to a pipe, start a recorder unless they use `--once`:
  run them with `--no-record` added, and say so in the report.
- **Never run** `record` or `stop` in any form, or any example the rules
  above forbid (installing, `bin/setup-hooks`, git commands that change
  state, releasing). Check those by reading them against the code and the
  `--help` output, and list them as "checked, not run".
- Write the demo history into a fresh scratch directory first, as in
  AGENTS.md's Manual Testing:

  ```sh
  demo="$(mktemp -d)/history.jsonl"
  timeout 3 ruby script/demo_history.rb "$demo"   # exit status 124 is expected
  ```

## Process

### 1. Extract the examples

Collect commands in fenced blocks (`bash`, `sh`, `shell`, `console`) and in
indented code blocks (the README uses these), and inline code that is
clearly a runnable command. Note any output shown with them.

### 2. Run each example

1. Run it from the project root, in its safe form (see Safety).
2. Create any files the example assumes in a temporary directory, not in the
   repository.
3. Check the exit code (0 unless the docs show a failure), compare the output
   with the documented output (ignoring values that legitimately vary, such
   as times, percentages, and absolute paths), and check that documented
   error examples produce that error.

### 3. Record failures

For each failure, record the file and line, the command, the documented and
actual results, and a suggested fix to either the documentation or, if the
code looks wrong, the code.

## Common Causes

- Renamed or removed options and commands
- Changed output, column names, or error text
- Working-directory or path assumptions
- Missing setup steps

## Output Format

If every example passes, report that briefly:

```text
Tested X examples across Y files; all passed. Checked, not run: Z (listed below).
```

Otherwise, write a report like this:

~~~markdown
# Documentation Example Test Results

**Date:** YYYY-MM-DD
**Tested Files:** X
**Total Examples:** Y
**Failed:** Z

## Failures

### README.md

#### Line 215: --utc

**Command (as run):**
```bash
bundle exec exe/claude-limit-watch --utc --once --file "$demo"
```

**Expected:** The panel, with times in UTC

**Actual:** ...

**Suggested Fix:** ...

## Checked, Not Run

- `README.md` line 234: `claude-limit-watch record ...` (starts a recorder)

## Summary

- ...
~~~

Give the report in your final message; don't write a file unless asked. Do
not modify files, open issues, or commit. The report is the deliverable; the
user decides which fixes to make.
