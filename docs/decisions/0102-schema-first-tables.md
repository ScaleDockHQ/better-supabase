# 0102: Tables are user-owned SQL; features are `@bsb` tags

- Status: accepted
- Date: 2026-10-25

## Context

`appTables`, `records` and the per-table config keys render tables into hashed
`900_better_supabase_*` files, and intent is read back with regexes. Supabase's declarative
schemas (`db schema declarative sync`, pg-delta) compare catalog facts and ignore file names, so a
user-owned file for each table fits the platform better than generated tables.

## Decision

- Tables live in `supabase/schemas/<schema>/tables/<name>.sql` in pg-delta's export layout. After
  `better-supabase migrate schema-first` writes them once, the user owns them.
- Per-table features are `@bsb` tags in the table comment, for example
  `comment on table invoices is 'Invoices. @bsb subject title=number; realtime; audit'`. Free text
  and tags coexist; only the tag block is parsed. Tags replace `realtime.tables`, `expose`, `json`,
  `vectorSearch`, the audit table lists, `subjects`, `records`, `encrypted`, `events` and
  `auditReads`.
- Column formats become domains (`bsb.email`). Rollups and lookups become `security_invoker` views.
- Block files stay generated and hashed, in `_better_supabase/`. Statements on user tables keep the
  `bsb_` prefix.
- `gen` reads tags from the catalog. `appTables` and `records` are removed (breaking), and
  `migrate schema-first` rewrites a config into SQL plus tags.

## Alternatives considered

- Security labels instead of comments: comments are visible in every tool, and tags coexist with
  free text.
- Keep generating tables: the user can't own them and tools that read the schema see two truths.

## Consequences

A breaking release with a migration guide, a codemod and a changeset.
