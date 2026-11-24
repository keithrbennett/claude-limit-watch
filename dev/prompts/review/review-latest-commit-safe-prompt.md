# Review Latest Commit (claude-limit-watch)

Review the latest commit and any uncommitted changes.
Report only issues needing addressing.

Begin the report with the full hash and subject of the commit reviewed
(from `git log -1 --format='%H %s'`).

Evaluate whether the changes are:

- Correct and complete.
- As simple as practical.
- Consistent with the commit's intent.
- Accompanied by appropriate tests and documentation updates.

The commit message may describe an implementation strategy rather than the
underlying problem. Infer the intended outcome and assess whether a better
solution would be appropriate.

## Safety: processes and the real history file

This tool runs a long-lived background recorder for the user, writing to
the state directory: `$XDG_STATE_HOME/claude-limit-watch/`, or
`~/.local/state/claude-limit-watch/` when `XDG_STATE_HOME` is unset or
empty. It holds the history file, its `.lock` file and `recorder.log`. A
previous review killed the recorder. Follow these rules strictly:

- **Never send a signal to a process you did not start yourself.** That
  means no `kill`, `pkill` or `killall` on anything else, and no
  `claude-limit-watch stop`, which signals whatever recorder holds the
  lock.
- **Never read from or write to the state directory** (either location
  above). Don't modify, delete or lock anything there.
- **Give every `exe/claude-limit-watch` run but `--help` and `--version`
  a history file under a scratch directory,** with
  `--file "${TMPDIR:-/tmp}/<dir>/history.jsonl"`. (`$TMPDIR` is often
  unset on Linux; without the `:-/tmp` fallback the path would land at the
  filesystem root.) Do this for every other command, every time.
  (`--help` and `--version` print and exit before touching any file.)
  Changing or unsetting `HOME` or `XDG_STATE_HOME` instead is not a
  substitute: without `--file`, a run can still reach the real history
  file and its recorder.
- **Never start a recorder, even briefly or under `timeout`.** A recorder
  calls the real usage API with the user's OAuth token, so even one on a
  temporary file adds to the user's rate limit, and `timeout` doesn't
  reliably end it. The viewer's is worse: it starts it detached, with
  `nohup` in its own process group, so it outlives the viewer and any
  `timeout`. So never run:
  - `record`, in any form.
  - The viewer without `--once` or `--no-record`. That includes `--lines`
    and output to a pipe (unless with `--once`), which start a recorder
    too.
  - In-process code (`ruby -e`, a script) that calls `Recorder.run`,
    `Recorder.start`, `Recorder.ensure_running`, `Recorder.stop` or
    `UsageApi.fetch_five_hour` without stubbing them. Calling functions
    that only compute or format, such as `Recorder.stop_command`, is fine.
- **These runs are fine,** with the history file in a scratch directory
  as above (except `--help` and `--version`, which need none):
  - `--help`, `--version`, and runs with invalid arguments.
  - `--once` (prints the panel and exits; it never starts a recorder).
  - The viewer with `--no-record`, under `timeout`, for example
    `timeout 3 exe/claude-limit-watch --lines --no-record --file
    "${TMPDIR:-/tmp}/x/history.jsonl"`. It only reads the history file: it never
    starts a recorder or calls the network.
- **Make sure the specs isolate themselves.** `bundle exec rspec` is safe,
  because the specs use a temporary history file and stub
  `Process.spawn`/`Process.kill`. If you change how the specs run, confirm
  they still do both.
- **If you start a process anyway, stop it yourself by its pid,** and say
  so in your report.
- **Write only to your scratch directory and to files the tools write
  themselves** (such as `coverage/` and RuboCop's cache): never install
  anything (`gem install`, `bundle install`), change git state or config
  (reading and `git fetch` are fine), run `bin/setup-hooks` or
  `bin/pre-release-check`, or release. See
  "Safety: the Host and the Repository" in AGENTS.md. A previous review
  overwrote the user's installed `agent-council` executable by installing
  a test gem.

## Scope

- Report only issues introduced by the latest commit or uncommitted changes.
- Report issues in uncommitted changes separately from those in the commit.
- Don't review or report on files that git ignores (check with
  `git check-ignore`), or on `agent-council-reports/` (agent-council's
  output, which may not be ignored). You may read ignored files for
  context, but they are local to this checkout, so judge the changes
  against tracked files.
- Do not report preexisting issues unless the changes introduce or worsen them.
- You may suggest improvements to the commit message, particularly if the
  commit has not been pushed.

## Verification

Investigate thoroughly before reaching conclusions.

You are permitted and encouraged to inspect files, run Git commands, execute
relevant tests and linters, and reproduce suspected defects, within the
safety rules above.

**DO NOT EDIT ANY CODE OR TRACKED FILES.**

Tests and linters that generate temporary files or coverage data are
permitted. Builds are permitted only when the gem lands outside the
working tree: run `gem build` in a scratch copy of the repo (for example,
one made with `git archive HEAD | tar -x -C "$(mktemp -d)"`). Never build
in the checkout itself, so no `rake build` (which writes `pkg/`) and no
`gem build` from the repo root.
Direct their output to your scratch directory (`${TMPDIR:-/tmp}`) where the tool
allows it. Avoid unnecessary modifications to the working tree.

To check behavior without a gem (for example, RSpec missing), put a stub on
the load path from `${TMPDIR:-/tmp}` rather than uninstalling anything. For example,
a `rspec/core/rake_task.rb` that raises `LoadError`, used with `ruby -I`.

For each issue, identify the affected file and location, explain the problem
and its impact, and propose a fix. Say how you verified it (for example, a
reproduction or a test run), or that it is unverified.
