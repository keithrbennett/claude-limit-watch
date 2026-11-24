# Release Notes

## 0.2.0 (unreleased)

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
