# Changelog

## 0.1.0 (2026-11-23)

First release as a gem.

- Background recorder that checks the 5-hour usage every 5 minutes (or a
  chosen interval) and keeps a JSON Lines history; `stop` stops it.
- Full-screen panel: quota used, time elapsed, and projection bars for
  the rates of the last 10m, 30m, 1h, 2h and the whole window, showing when
  each rate would reach the limit and how long you'd be locked out.
- `--lines` output (one line per reading) and `--once` (print the panel
  once and exit).
- `--no-record`: view the history file without starting a recorder.
- `--utc`: show times in UTC instead of local time.
- `--file PATH` (any command): the history file to use.
- `--help` and `--version`.
