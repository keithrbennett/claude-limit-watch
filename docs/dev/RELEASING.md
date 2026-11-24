# Releasing

[Back to the README](../../README.md)

A checklist for releasing a new version of claude-limit-watch. Tagging,
pushing, and `gem push` stay manual (`gem push` asks for an MFA code).

## 1. Prepare

- [ ] Set the version in `lib/claude_limit_watch/version.rb`, following
  [Semantic Versioning](https://semver.org/).
- [ ] In `CHANGELOG.md`, rename `## Unreleased` to `## VERSION (YYYY-MM-DD)`,
  and add a new, empty `## Unreleased` above it. Make sure every
  user-visible change is listed.
- [ ] Check that the README's usage, options, and screenshot are current.
- [ ] Optionally, have an agent follow
  [dev/prompts/review/release-review.md](../../dev/prompts/review/release-review.md)
  for a checklist of what's left.
- [ ] Run the checks locally (the pre-commit hook runs the first two; the
  link check needs Docker, and CI runs it too):

```sh
bundle exec rubocop
bundle exec rspec
docker run --rm -v "$PWD":/input:ro -w /input lycheeverse/lychee:0.24.2 \
  --offline --include-fragments --no-progress --extensions md .
```

## 2. Commit and push

```sh
VERSION=0.2.0   # the new version
git add lib/claude_limit_watch/version.rb CHANGELOG.md   # plus any docs you changed
git commit -m "Release $VERSION"
git push origin main
```

## 3. Check and build

```sh
bin/pre-release-check
```

It stops at the first problem. It checks that:

- the working tree is clean, and you're on `main`, in sync with
  `origin/main`;
- `CHANGELOG.md` has a `## VERSION (YYYY-MM-DD)` section (and warns if `## Unreleased`
  still has entries);
- the tag `vVERSION` doesn't exist yet;
- the newest push or manual CI run (`.github/workflows/ci.yml`) for HEAD
  passed. It watches a run still in progress, and just after a push it
  waits up to a minute for GitHub to list the run. If the run failed, it
  names it; if there's none, it prints the command that starts one.

Then it builds `claude-limit-watch-VERSION.gem` once, in the repository
root (gitignored), installs it into a scratch gem directory, and runs it
from there (`--version`, `--help`, and `--once` on a scratch history
file). Finally it prints the commit and the
gem's SHA256, and the commands for the next steps.

That gem file is the release artifact: don't rebuild it. (Rerunning the
script rebuilds it, with a new SHA256; publish the one from the last run.)
The gem's file
list comes from `git ls-files`, and the script builds only from a clean,
pushed `main`, so the gem matches the commit you'll tag.

It needs the GitHub CLI (`gh`), logged in (`gh auth status`) with read
access to the repository's Actions.

## 4. Tag and publish

Run the commands the script printed, which name the version, the commit,
and the gem's full path. They are, in the form:

```sh
git tag -a vVERSION -m 'Version VERSION' COMMIT-SHA
git push origin vVERSION
gem push /path/to/claude-limit-watch/claude-limit-watch-VERSION.gem
```

Before `gem push`, you can compare the gem's hash with the one the script
printed: `sha256sum` (macOS: `shasum -a 256`) on that file.

Then check that the new version is listed at
<https://rubygems.org/gems/claude-limit-watch>, and optionally create a
GitHub release from the tag, with that version's CHANGELOG section.

## If a release is broken

Yank it (`gem yank claude-limit-watch -v VERSION`), fix the problem, and
release a new patch version.
