# 0244: Store templates as rows of the record they create

- Status: accepted
- Date: 2026-11-06

## Context

A template for a task, quote or invoice used to need a mirror table for every
child table, kept in sync by hand. The generated block SQL treats every row as
a live record, so a template row would take a number, enter search, start
pipelines and emit events. Apps cannot edit the generated files.

The `templates` block already stores a template's identity, versions, forks and
the link to the record it created.

## Decision

A template is a row in `templates`. Its content is a versioned body, or rows in
a templatable table whose `template_id` points at that row. Blocks opt in with
`options.templates`. An app table opts in with the `@bsb template` tag, which
calls `template_table`. The column is also a subject key, so numbering, search,
pipelines, the state machine, metrics and list reads skip the row from one
place. Audit still records the edit.

`clone_<entity>` copies a row and its block-owned children. `instantiate_template`
dispatches a body template to the existing apply target and a rows template to
that clone, then writes `template_applications`. `pack_template` and
`unpack_template` move rows templates through the version body, so starters and
forks stay portable. Types are declared in `blocks.templates.options.types` or
contributed by a block. With the option off, the record tables gain no template
column. The clone functions are always generated, so Duplicate can use them.

## Alternatives considered

Mirror tables per child stay in sync only by repeating every bug fix. Skipping
the side effects in application code cannot work, because the triggers are
generated. A second template system beside `templates` would split identity,
versions and forks.

## Consequences

A fix to quote lines or task checklists applies to templates. Turning the
option on requires the `templates` block and a migration that adds the columns.
Relative dates and variable substitution are read from the type's rules when a
template is instantiated.
