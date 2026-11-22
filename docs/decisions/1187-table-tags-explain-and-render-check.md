# 1187: Explain table tag moves and check that the tag reaches the render

- Status: accepted
- Date: 2026-11-22

## Context

`codemod table-tags` moves audit exemptions, `data-lifecycle` tables and `expose`
entries from the config into `comment on table` tags. It did not say what it
would do before it wrote, and it did not prove that a tag gives back the value
the entry held. An `audit-exempt` tag changes nothing in the render, because only
doctor reads it, while `data-lifecycle` and `grant` tags reach the render through
`withSchemaTags`.

## Decision

- `--explain` lists each entry that moves with its tag line and says where the
  tag reaches: doctor only, or the render. It writes nothing.
- Before a `data-lifecycle` or `grant` entry moves, the codemod removes the entry
  from the config, reads the tag through `withTableTags` and compares the result
  with the entry. A difference keeps the entry in the config and prints the
  reason.

## Alternatives considered

- Render the blocks before and after, as `config --prune` does: the tags are read
  at config time, so comparing the config value proves the same thing with no
  render.
- Make `--explain` a mode of every codemod: only `table-tags` has tag-only
  semantics, so the flag stays specific to it.

## Consequences

An entry that the tag cannot reproduce stays in the config with a review line.
`audit-exempt` moves are always safe for the render, and the explain output
says so.
