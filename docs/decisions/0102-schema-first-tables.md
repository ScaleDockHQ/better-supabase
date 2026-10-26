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

## Addendum: tag formats `gen` reads

- `subject`, `realtime` and `vector-search` keep their arguments from the config keys they replace.
- `json` takes `column=Type` pairs, or `column=import:module#Name`; `encrypted` takes `column=type`
  pairs (a bare column is text); `events` takes `on` and `include` as comma lists.
- `audit`, `audit-reads` and `expose` change the table's SQL only (the audit trigger, the reveal
  audit and the grants live in the table's own file), so `gen` reads nothing from them.
- A key the config sets itself wins over a tag, so a project moves one table at a time.

## Addendum: the SQL modules read tags too

- `loadConfig` reads the `@bsb` comments in the declarative schema files and adds `subject`,
  `realtime`, `vector-search` and `json` entries to the resolved config, so `upgrade`, `gen` and
  doctor see one config. `appTables` is never filled from tags: the tables' SQL is already in the
  files.
- `subject` takes `type`, `id`, `id-type`, `tenant` (`false` for none), `title`, `url`, `scope`,
  `cascade`, `deleted-at`, `search` (bare), `search-title`, `search-body`, `search-description`,
  `search-exclude`, `rank`, `rank-group`, `versions` (comma list), `versions-auto=false` and
  `can-<action>=<permission>`. Subjects that need `search.from`, `search.watch` or row grants stay in
  `subjects`.
- Dropping `tables` removes the `appTables.set` bulk action, because the bulk module adds it only
  for a config with app tables.
- `server` lists the columns signed-in users can't read (the column grants already exclude them),
  so `gen` types them as not selectable.

## Addendum: stage 3 removes `tables` and `records`

- The grouped config has no `tables` key and `records` is `subjects` (0.28). Config loading refuses
  both with a message that names the replacement; only `migrate schema-first` reads them.
- Create keeps `appTables` inside its design format and `create/lite`, so the cloud app is
  unchanged. `init --preset` and `add --preset` render the design's tables to SQL files with
  `policy: "create"`, so a table file you edited is kept.
- The preset breaking-change report goes with the config key: `db diff` plans renames and reports
  data loss from the SQL files.
