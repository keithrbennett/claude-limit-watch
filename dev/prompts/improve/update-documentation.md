# Review and Revise Documentation as Necessary

**Purpose:** Keep the project's Markdown documentation accurate, clear, complete, and internally consistent.

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read [AGENTS.md](../../../AGENTS.md).

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

---

## Scope

Examine all tracked Markdown files at the repository root (`*.md`) and in
`docs/**/*.md`, and the prompt index, `dev/prompts/README.md`.

Exceptions:

- `CHANGELOG.md`: each released section describes that release as it
  shipped. Fix typos and broken links only; update only the `## Unreleased`
  section for current changes.
- The prompts in `dev/prompts/` (other than the index) are not
  documentation; leave them alone unless they reference something that no
  longer exists.

## What to Look For

### Accuracy

- Claims that no longer match the code (CLI flags, method names, output formats, file paths).
- Code examples that produce different output than documented, or that refer to removed features.
- Version numbers, dependency names, or configuration keys that have changed.

### Clarity

- Sections that assume prior knowledge not provided in the doc or a clearly-linked prerequisite.
- Ambiguous pronouns or unexplained jargon — if the meaning is unclear on first read, rewrite it.
- Paragraphs that mix distinct topics; split or reorganise them.
- Over-long explanations where a concise rewrite would preserve meaning with less noise.

### Completeness

- Missing prerequisites: if a command requires setup, the setup must be described or linked.
- Gaps between what a feature does and what the docs say it does.
- New commands or options not yet documented.

### Link Integrity

Check internal links (relative Markdown paths) and anchor links (`#heading-id`):

- Verify that the target file exists at the referenced path.
- Verify that named anchors (`#section-name`) match an actual heading in the target document.
- Check that bidirectional navigation links exist where expected (e.g., the README links
  to a specialist doc, and that doc links back with text like `Back to the README`).

### Duplication

- If the same point is explained in multiple documents, decide which is the canonical location
  and replace the others with a brief note and a link to it.
- Do not duplicate content that is already maintained elsewhere — link instead.

### Code Examples

- Confirm that shell/CLI examples use current flag names and produce valid output.
- For thorough validation of all runnable examples across the docs, use
  [`dev/prompts/validate/test-documentation-examples.md`](../validate/test-documentation-examples.md).

## Actions to Take

1. **Fix in place** — edit the doc file directly; no separate report is needed
   unless the scope of changes warrants a summary.
2. **Prefer linking over duplicating** — when the same information belongs in
   two places, keep the authoritative copy and add a short cross-reference
   elsewhere.
3. **Match existing tone** — keep edits consistent with the surrounding prose style.
4. **Do not rewrite for rewriting's sake** — only change what is inaccurate, unclear, or missing.

## Constraints

- Treat the code as the source of truth. Do not alter code files; if the code
  looks wrong rather than the docs, report it instead.
- Verify claims by running the CLI rather than trusting the existing text,
  within the safety rules above.
- Do not stage or commit. End by summarizing what you changed and why,
  and propose, for the user to run, a paste-ready `git add` of only the
  documentation files you changed and a `git commit -F -` command with a
  message saying what was corrected and why.
