# Release Review

**Purpose:** Produce a checklist of what still needs to be done to release
claude-limit-watch, based on the actual state of the repository. It works
both before and after the version and CHANGELOG are updated. This is
advisory: `bin/pre-release-check` is the hard gate.

## When to Use This

- At any point, to answer "what would I need to do to release?"
- After updating the version and CHANGELOG, before committing and pushing
  ("what is left?")

It does not replace `bin/pre-release-check`; it does not verify CI, the
clean tree, or the built gem.

---

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Open the report by citing the most recent git commit.
3. Run `git status`. List any uncommitted changes. They are expected if the
   version and CHANGELOG were just updated; otherwise note them as items to
   resolve.
4. Limit the review to git-tracked files, plus untracked files reported by
   `git status` (for the cleanup step).
5. Read [AGENTS.md](../../../AGENTS.md), and follow the safety rules
   below for every command.

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
- Don't build the gem.

---

## Your Role & Task

You are a release manager. Read `docs/dev/RELEASING.md` (the canonical
checklist, which may have changed since this prompt was written) and
determine, from the repository's actual contents, the status of every item
that requires judgment. Do not run the specs or RuboCop: CI runs them on every
push, and `bin/pre-release-check` confirms CI passed for the commit being
released. (Running them locally is still a step in `docs/dev/RELEASING.md`;
list it as remaining unless the maintainer says it's done.)

### 1. Establish the release state and target version

- Read `VERSION` from `lib/claude_limit_watch/version.rb`, the `## Unreleased`
  section of `CHANGELOG.md`, and the newest `## X.Y.Z (YYYY-MM-DD)` heading.
- Find the previous release tag (`git tag --sort=-v:refname`).
- Decide whether the version has been bumped. It **has** if the newest dated
  heading matches `VERSION`, `vVERSION` isn't tagged yet, and `## Unreleased`
  is empty. It **has not** if there is content under `## Unreleased`, or
  `VERSION` is already tagged. If the state is ambiguous, say so and ask.
- Determine the target version:
  - Bumped: the target is `VERSION`.
  - Not bumped: if the user named a target version, use it. Otherwise
    recommend one using semantic versioning from the changes found in step 2
    (breaking change: major, or minor while below 1.0; new feature: minor;
    fixes only: patch), explain the reasoning, and label it a recommendation
    for the maintainer to confirm. Do not ask before proceeding; continue the
    review against the recommended version.

### 2. Compare changes against the CHANGELOG

- Review `git --no-pager log --oneline <previous-tag>..HEAD` and
  `git --no-pager diff --stat <previous-tag>..HEAD`, then the diffs that
  matter: `lib/` and `exe/` for user-visible changes, and the rest (CI,
  `bin/`, `script/`, `dev/`, specs) for the CHANGELOG's Development
  entries.
- Compare against the CHANGELOG section for this release: the dated section
  if bumped, or `## Unreleased` if not.
- List user-visible changes (commands, options, the panel and `--lines`
  output, the history file format, the recorder's behavior, error messages,
  the Ruby version requirement) that are missing from it.
- List entries that do not correspond to any actual change.
- Flag any incompatible change, especially to the history file format, that
  the entry doesn't call out.

### 3. Documentation accuracy

- Spot-check the README against the changes found in step 2: examples,
  option names, defaults, and the `--help` output
  (`bundle exec exe/claude-limit-watch --help`).
- Check whether `docs/images/panel.png` still matches the panel, if the
  panel changed.
- For a thorough example check, recommend
  `dev/prompts/validate/test-documentation-examples.md` rather than doing it
  here.

### 4. Cleanup

- From `git status`, classify each untracked or modified file as: commit,
  add to `.gitignore`, delete, or expected release change.

### 5. Remaining process steps

List the not-yet-done steps from `docs/dev/RELEASING.md`, in order, marking any
that the repository state shows are already done (for example, an existing tag
or an `origin/main` that matches `HEAD`). Run `git fetch origin --tags` first,
so `origin/main` and the tags are current; it changes no local branch.

---

## Output Format

Open with the commit citation, then:

- Bump state (done or not done) and the evidence
- Previous release tag
- Target version (given, or recommended with reasoning)

Then give a single checklist, grouped by the sections above:

- `[ ]` needs action, with the file path and what to do
- `[x]` verified OK, with a few words of evidence
- `[?]` needs the maintainer's judgment, with the question to answer

Put all `[ ]` and `[?]` items first in a short "Before you bump" (or, if the
bump is done, "Blocking before commit") summary. Where a gap suggests a script
improvement (for example, a check that could be automated in
`bin/pre-release-check`), mention it at the end as a prompt the maintainer can
use later. Do not implement it.

Give the checklist in your final message; don't write a file unless asked.
Do not edit files, stage, commit, tag, or push.
