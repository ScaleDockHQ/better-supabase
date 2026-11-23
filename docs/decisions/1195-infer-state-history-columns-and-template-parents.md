# 1195: Infer state history actor columns and template child parents from the schema

- Status: accepted
- Date: 2026-11-22

## Context

A state machine with an app history table names each actor column
(`actorName`, `actorEmail`, `ip`, `userAgent`) even when the table declares them
under their usual names. A rows template lists each child table with the column
that references the root row, which the schema files already say through the
foreign key.

## Decision

- The layout carries the columns each declared table has (`declaredColumns`) for
  the modules that read them, and the module context exposes them. A history table
  that declares `actor_name`, `actor_email`, `ip` or `user_agent` writes them
  without a config entry. A name in the config still wins.
- A child of a rows template needs no `parent` when the schema declares exactly
  one single-column foreign key from the child to the root table. Zero or more
  than one is an error that names the count.

## Alternatives considered

- Infer the child tables too: any table with a foreign key to the root would join
  the pack, including tables the app never meant to copy.
- Infer the `from`, `to` and `subject` history columns: their conventional names
  are required anyway, and a missing column is a doctor finding already.

## Consequences

`config --prune` removes the entries these defaults make redundant, because it
renders with and without each one. A history table that declares an `ip` column
for another purpose now receives the actor's address; name the column
differently in the schema to avoid it.
