# 1190: Blocks create their tables first, and the app extends or maps them

- Status: accepted
- Date: 2026-11-22

## Context

A project that adopts a block over its own table writes a `tables` entry for the
table and a `columns` entry for each column whose name differs. CentraKit has 34
`tables` entries that only name the block's default table in the schema the app
uses, and 206 column entries that differ from the convention. The entries repeat
a fact the schema files already hold, and `appFields` (the generator's list of
columns the app adds to a block's table) read only the table a removed option
named, so a block without one (memberships, or any block that owns several
tables) generated no `fields` for the columns the app added.

## Decision

The block's names are the default, and a project reaches them in three ways.

- Base-first: the block creates its table under its own names in the schema its
  `schema` key names, and the app adds columns and constraints with
  `alter table`. `appFields` takes the first table of the block that the app
  extends, so the generated `fields` carry the columns for every block.
  `tests/validation-declarative` proves that the block creates the table, the
  app's statements stay untouched and a second upgrade changes nothing. The
  nightly shadow-database sync covers the empty plan.
- Tags: `@bsb block-table=<block>.<table>` on a table comment and `@bsb
  column=<column>` on a column comment map an app table that keeps its names.
  They fill the block's `tables` and `columns` below the config, so an entry in
  the config wins.
- `codemod adopt-names --table <block>.<table>` renames one table to the
  block's names: a hand migration with the renames, a rewrite of the app's schema
  files through the SQL scanner (a statement that names the table, its
  qualified or bare name and its mapped columns), the removal of the `tables`
  and `columns` entries, and a list of the generated types that change. It
  refuses a table outside the block's schema, and a `values` entry stays,
  because stored labels need a data migration.

## Alternatives considered

- Rewrite every column reference in every statement: a column name that other
  tables share would change by mistake. The codemod renames columns only in
  statements that name the table, and prints a review line for each file.
- Remove the `values` entries with the others: the entry maps labels, not names,
  so removing it changes behavior.
- Move a table into the block's schema in the same run: it changes the Data API
  exposure, so the codemod asks for the block-level `schema` first.

## Consequences

An app that wants the block's names runs the codemod per table and reviews the
migration. An app that keeps its names writes two comments instead of config
entries. The scanner rewrite does not follow a table through an alias or a
bare column outside a statement that names the table, so the review line asks
for a check.
