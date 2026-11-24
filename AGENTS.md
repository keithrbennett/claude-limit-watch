# AGENTS.md – Agent Guide

[Project overview in README](README.md)

This file provides guidance to Codex, Claude Code (claude.ai/code), Gemini CLI, and any related agents when working with this repository. Treat it as the canonical reference for workflows, tooling, and expectations; update it directly whenever new agent instructions are required.

If `untracked/AGENTS.local.md` exists (gitignored, so local to one checkout), read it too: it holds that checkout's personal workflow additions.

## Mission
- Keep workflow transparent: explain what you did, why it matters, and what the user should consider next.
- Leave the repository tidy; only touch files that advance the request. If you find
other opportunities for improvement along the way, mention them in the form of a prompt the user can use later.
- Never disturb the user's running recorder or real history file. See [Safety: the Recorder and the Real History File](#safety-the-recorder-and-the-real-history-file); those rules override anything else here.

## Running External Commands

- When running shell commands on this project, use a Bash login shell where possible: run commands via bash -lc '<command>' (or the platform's equivalent) rather than relying on the default shell.
- If practical, use workdir features of the agent rather than relying on `cd` in the command string

## Environment & Execution

Prefer project-local tools and scripts (Rake tasks, `bin/` and `script/`) instead of ad-hoc one-off commands when building, testing, or running the project.

- Prefer `rg`/`rg --files` for searches; switch only if ripgrep is unavailable.
- Codex sandbox: workspace write access; network is restricted. Request escalation (`with_escalated_permissions` + short justification) only when indispensable.
- Codex approval mode is `on-request`: retry failed-but-needed commands with escalation rather than asking the user manually.
- Codex planning tool: skip for trivial chores; otherwise create a multi-step plan and keep it updated as you work (max one `in_progress` step).
- Prompts in `dev/prompts/` that write reports put them in `untracked/` (gitignored; create it if missing) unless the invocation names another location.
- For commit reviews, use `dev/prompts/review/review-latest-commit-safe-prompt.md`: it adds this repo's recorder safety rules to the generic `review-latest-commit-prompt.md`.
- When moving or renaming tracked files, use `git mv` (or `git mv -k`) instead of plain `mv` so history stays intact.

## Ruby Guidelines
- Use any supported Ruby (2.6 or later); there is no `.ruby-version`.
- Prefer `bundle exec` for project tools.
- Run `bundle exec rake`, `bundle exec rspec`, and `bundle exec rubocop`; this repo has no binstubs for them (`bin/` holds project scripts).
- Before editing, inspect:
  - `Gemfile`
  - `Gemfile.lock` (gitignored, so local to the checkout)
  - `*.gemspec`
  - `.rubocop.yml` and `.rubocop-shared.yml` (which it inherits)
  - `.rspec`
- Run the smallest relevant test first.
- Preserve existing Ruby idioms.
- Do not add gems unless necessary. The gem has no runtime dependencies (standard library only) and must stay that way.
- If `ruby-lsp` is available, prefer symbol-aware analysis over broad file dumping when the tool supports that workflow.

## Project Overview
`claude-limit-watch` is a Ruby gem that watches a Claude subscription's 5-hour usage limit. It reads usage from an undocumented endpoint (the one Claude Code's own usage display uses), with the OAuth token Claude Code stores locally, and sends that token only to `api.anthropic.com`.

### Recorder and Viewer
The single executable, `claude-limit-watch`, has two roles:
- **Recorder** (`record`): checks the usage at intervals and appends each reading to the history file (`~/.local/state/claude-limit-watch/history.jsonl` by default). The viewer normally starts it in the background; a lock ensures only one runs at a time.
- **Viewer** (`view`, the default): reads the history file and shows a full-screen panel (or one line per reading with `--lines`, or when output isn't a terminal) projecting when the limit will be reached at recent burn rates. Unless given `--once` or `--no-record`, it starts a detached recorder if none is running.

Code map: `lib/claude_limit_watch.rb` (the entry point; requires the rest), then in `lib/claude_limit_watch/`: `version.rb` (version and homepage), `cli.rb` (command line), `usage_api.rb` (the endpoint), `recorder.rb`, `history.rb`, `snapshot.rb` and `projection.rb` (the numbers), `panel.rb` and `lines_view.rb` (the two views), `format.rb` and `term.rb` (text, colors, terminal).

## Safety: the Recorder and the Real History File

The user runs a long-lived background recorder writing to the state directory: `$XDG_STATE_HOME/claude-limit-watch/`, or `~/.local/state/claude-limit-watch/` when `XDG_STATE_HOME` is unset or empty. It holds the history file, its `.lock` file, and `recorder.log`. An agent review once killed the recorder. Follow these rules strictly:

- **Never send a signal to a process you did not start yourself.** No `kill`, `pkill`, or `killall` on anything else, and no `claude-limit-watch stop`, which signals whatever recorder holds the lock.
- **Never read from or write to the state directory** (either location above). Don't modify, delete, or lock anything there.
- **Give every `exe/claude-limit-watch` run a history file under a scratch directory**, with `--file "${TMPDIR:-/tmp}/<dir>/history.jsonl"`, every time. (`$TMPDIR` is often unset on Linux; without the `:-/tmp` fallback the path would land at the filesystem root.) Changing or unsetting `HOME` or `XDG_STATE_HOME` instead is not a substitute.
- **Never start a recorder, even briefly or under `timeout`.** A recorder calls the real usage API with the user's OAuth token, adding to the user's rate limit, and the viewer starts it detached (`nohup`, own process group), so it outlives the viewer and any `timeout`. So never run:
  - `record`, in any form.
  - The viewer without `--once` or `--no-record` (including `--lines` and output to a pipe).
  - In-process code that calls `Recorder.run`, `Recorder.start`, `Recorder.ensure_running`, `Recorder.stop`, or `UsageApi.fetch_five_hour` without stubbing them. Functions that only compute or format are fine.
- **These runs are fine** (with the history file in a scratch directory): `--help`, `--version`, invalid arguments, `--once`, and the viewer with `--no-record` under `timeout`.
- **Specs isolate themselves**: they use a temporary history file and stub `Process.spawn`/`Process.kill`. If you change how the specs run, confirm they still do both.
- **If you start a process anyway, stop it yourself by its pid,** and tell the user.

## Building, Running, and Testing

### Running Tests
Run the full suite with:
```sh
bundle exec rspec
```
You can also run the default Rake task (the specs; RuboCop is separate because it can't run on Ruby 2.6):
```sh
bundle exec rake
bundle exec rake rubocop
```
Use `bundle exec rspec spec/panel_spec.rb` to target specific specs when needed.

On Ruby 3.2 or later (SimpleCov 1.x's minimum), the specs also write coverage to `coverage/` (gitignored), including `coverage.json` for the cov-loupe MCP tools; they skip it, with a warning, if SimpleCov can't be loaded or is older than 1.0, or if `coverage/` can't be written. On older Rubies they run without coverage.

### Manual Testing
Follow the safety rules above. For example:
```sh
bundle exec exe/claude-limit-watch --help
demo="$(mktemp -d)/history.jsonl"   # a fresh directory, so concurrent runs don't collide
# The demo script writes a made-up history, then keeps it current until
# stopped; timeout's exit status 124 here is expected.
timeout 3 ruby script/demo_history.rb "$demo"
bundle exec exe/claude-limit-watch --once --file "$demo"
timeout 3 bundle exec exe/claude-limit-watch --lines --no-record --file "$demo"
```

## CLI Usage

Run `bundle exec exe/claude-limit-watch --help` for up-to-date usage information.

## Development Conventions
- Target Ruby >= 2.6 (macOS's system Ruby): no syntax or standard-library APIs newer than 2.6. RuboCop's `TargetRubyVersion` is 2.6, and CI runs the specs on Ruby 2.6 through 4.0 on Linux and macOS.
- Use two-space indentation and `# frozen_string_literal: true` in Ruby files.
- Match existing style and patterns. Comments should clarify non-obvious logic only.
- Never undo or overwrite user changes outside your scope; integrate with them instead. However, if the new changes would be better implemented by modifying other sections, e.g., extracting now-duplicated behavior into a special method, then do that.
- When adding behavior, couple it with tests. Specs belong in `spec/<name>_spec.rb` for `lib/claude_limit_watch/<name>.rb` (shared helpers in `spec/support/`), and use RSpec (never minitest) with rspec-mocks for stubbing.
- Specs and documentation matter as much as code. Update the README and CHANGELOG when behavior changes, and don't describe spec or doc changes as low-risk because they don't change how the code runs.
- Keep config files (such as `.rubocop.yml`) consistent with the maintainer's other projects: never remove a setting because nothing currently uses it.
- The gem's file list (`claude-limit-watch.gemspec`) ships only files git tracks, so a new file under `lib/` must be added to git before the gem is built. CI fails if the built gem's files differ from the tracked ones.
- Validate meaningful changes with `bundle exec rspec` when feasible; note skipped verification in your summary if you cannot run it.

## Git Workflow
1. **Run Tests:** Always run RuboCop and the test suite to verify your changes before considering them complete:
   ```bash
   bundle exec rubocop # and then `bundle exec rubocop -A` if necessary
   bundle exec rspec
   ```
   The optional pre-commit hook (`hooks/pre-commit`, installed with `bin/setup-hooks`, which sets `core.hooksPath`) runs both before each commit.
2. **Committing:**
    - **Never commit or push.** Don't run `git commit`, `git push`, or anything else that writes history or reaches a remote (amend, rebase, tag). The maintainer reviews and commits every change.
    - **Propose a paste-ready command** instead: explicit `git add` of the changed files, `git commit -F -` with the message in a quoted heredoc (short subject; body wrapped at 72 columns). Never include a push to `main` or another real branch, unless `untracked/AGENTS.local.md` says otherwise.
    - **No AI attribution:** Do not add AI or agent credit lines (e.g., `Co-Authored-By: Claude ...`, `Claude-Session: ...`, "Generated with ...") to commit messages or PR descriptions.
3. **Selective Staging:** Never assume that all uncommitted files are intended to be committed. Do not use `git add .` or similar catch-all commands. Explicitly stage only the files relevant to the current task.
4. **Use `--no-pager`:** When running git commands that may produce long output (e.g., `git diff`, `git log`), include `--no-pager` between `git` and the subcommand to prevent paging issues in automated environments:
   ```sh
   git --no-pager diff
   git --no-pager log --oneline
   ```
5. **Releases:** Tagging, `git push`, and `gem push` are intentionally manual (e.g., MFA prompts). Do not flag missing automation for them.

## Response Expectations
- Be concise and collaborative. Lead with the change/insight; follow with necessary detail.
- Reference files with inline clickable paths (e.g., `lib/claude_limit_watch/projection.rb:42`). Avoid ranges and external URIs.
- When providing content intended for the user to copy and paste (like commit messages or configuration snippets), do not include line numbers or any other decorators that would interfere with direct usage.
- Summaries use plain bullets (`-`). Offer next steps only when they flow naturally (tests, commits, builds, validation).
- Do not dump entire files; mention paths. Keep tone factual, note open questions, and highlight testing gaps.

## Testing Notes
- Test files live in `spec/` and follow standard RSpec conventions.
- Where possible, make tests more DRY (concise) by iterating over arrays of test setups.
- If there are test errors that would never occur in production (i.e. that are errors due to the test environment and not logic errors), the agent should modify test code and not production code, and make the solution as simple as possible.

## RuboCop Linting

RuboCop is used to enforce consistent code styling and best programming practices.
Write code consistent with RuboCop configured rules, e.g. indentation and use of
`it_behaves_like` instead of `include_examples` in RSpec. RuboCop needs Ruby 2.7 or later; the `Gemfile` skips it on 2.6.

### Sandbox Environments

If running RuboCop in a sandboxed environment (e.g., AI coding assistants with file system restrictions), you may encounter cache write failures:

```
Read-only file system @ rb_sysopen
  → /home/user/.cache/rubocop_cache/...
```

**Workaround:** Use the `--cache false` flag:
```sh
bundle exec rubocop --cache false
```

## Documentation
- `README.md` – user documentation: installation, usage, the panel, the recorder, the history file, and how it works.
- `CHANGELOG.md` – changes by release.
- `CONTRIBUTING.md` – contribution process and development setup.
- `CODE_OF_CONDUCT.md` – the code of conduct.
- `docs/dev/RELEASING.md` – the release checklist, with `bin/pre-release-check` (its code is `script/pre_release_check.rb`, specced in `spec/pre_release_check_spec.rb`). `bin/pre-release-check` is for the maintainer: don't run it (it fetches from origin, builds a gem, and installs it into a scratch directory); its specs fake every command.
- `AGENTS.md` (this file) and `CLAUDE.md` (a pointer to it) – agent instructions.
- `docs/images/panel.png` – the README's panel screenshot, taken from the demo history written by `script/demo_history.rb`.

## Important Conventions
- Load library files with `require_relative` from `lib/claude_limit_watch.rb`, which requires them all in dependency order; add new files there.
- The executable name is `claude-limit-watch` (hyphenated).
- Send the OAuth token only to `api.anthropic.com`, and never log or print it.
