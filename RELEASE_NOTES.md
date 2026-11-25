# Release Notes

## 0.2.0 (unreleased)

### Panel

- **A one-line title.** The 3-row framed banner is replaced by one line:
  the name and version, centered on a lavender rule. The panel now looks
  the same at every terminal height, instead of dropping the banner when
  the terminal is too short.
- **The history file has a line of its own** at the bottom. A path too
  long for the terminal is shortened from the left, shown by `...`, so
  the file name stays visible (`--once` prints it whole). When the last
  reading was is now under the current time, in a column after a
  vertical bar (left out in terminals too narrow for it). The version
  and project page line is gone from the panel; the version is on the
  title line, and both are still printed on quitting, after `--once`'s
  panel, and in `--help`.
- **The no-data message no longer shows the history file's path,**
  which is now on the bottom line, and "no readings yet" is no longer
  repeated at the top.

### Packaging

- **The gem ships only files git tracks.** When it's built from a git
  checkout, untracked or ignored files in the working tree can't end up
  in it. CI checks that the built gem holds exactly those files.

### Documentation

- **`CHANGELOG.md` is now `RELEASE_NOTES.md`.** It's the name the
  maintainer's other gems use; the gem's `changelog_uri` points to it.
- **Contributing guidelines and a code of conduct:** `CONTRIBUTING.md`
  and `CODE_OF_CONDUCT.md`.

### Development

- **An agent guide:** `AGENTS.md`, with `CLAUDE.md` pointing to it.
- **Coverage reports.** On Ruby 3.2 or later, the specs write a SimpleCov
  coverage report to `coverage/`.
- **Dependabot** checks the development gems and CI actions weekly.
- **A release checklist,** `docs/dev/RELEASING.md`, and
  `bin/pre-release-check`.
- **Prompts for AI agents** in `dev/prompts/` (documentation, release,
  and code reviews), listed in `dev/prompts/README.md`.
- **Markdown link checks.** CI checks the Markdown files' relative links
  and anchors, with lychee.

## 0.1.0 (2026-11-23)

First release as a gem.

- **Background recorder:** checks the 5-hour usage every 5 minutes (or a
  chosen interval) and keeps a JSON Lines history; `stop` stops it.
- **Full-screen panel:** quota used, time elapsed, and projection bars
  for the rates of the last 10m, 30m, 1h, 2h and the whole window,
  showing when each rate would reach the limit and how long you'd be
  locked out.
- **`--lines` and `--once`:** one line per reading, or print the panel
  once and exit.
- **`--no-record`:** view the history file without starting a recorder.
- **`--utc`:** show times in UTC instead of local time.
- **`--file PATH`** (any command): the history file to use.
- **`--help` and `--version`.**
