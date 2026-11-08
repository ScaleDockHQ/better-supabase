# 0393: Close the declarative base layer release and record what is deferred

- Status: accepted
- Date: 2026-11-08
- Amends: 0232, 0373, 0387, 0388, 0392

## Context

The declarative base layer branch renames tables, columns, config keys, blocks,
hint codes, flags and exports (ADRs 0246 to 0388), moves block output to
declarative schema files, and makes the app's own tables the source of truth
(ADRs 0102 to 0105, 0250 to 0273). The release step has to say which ideas in
the plan shipped, which were decided against, and which wait for their own
design pass, so a later change does not reopen them by accident.

## Decision

### Decided

- The `rank` block keeps its name. It is the fractional-ordering block (base-62
  rank keys, ADR 0021). Ratings are reviews and scores (ADRs 0067 and 0076), so
  a `ratings` block would be a second home for them. ADRs 0387 and 0388 listed
  `rank` to `ratings` as not done; it is now decided against.
- The `powersync` publication is a migration-only object by default, and
  `declarative sync --strict-coverage` reports it as a drop, because pg-delta
  tracks publications and no schema file declares one. `powersync streams`
  now also writes `powersync_publication.sql` into the declarative schemas
  folder when the repo has one, listing every synced table in a
  `create publication powersync for table ...` statement. The migration it writes
  stays the way an existing database gets the change. A local check with a
  `create publication` migration and the same statement in `supabase/schemas`
  gives `No schema changes found`; without the file the sync proposes
  `DROP PUBLICATION "powersync"`. `tests/cli/commands/powersync.test.ts`
  holds the file.

### Deferred

Each item waits for a change of its own.

- The generated file layout (`schema.ts`, `tables/`, `blocks/<instance>.ts` and
  one `blocks/index.ts` barrel). It changes what a browser bundle imports, so it
  needs the client and server split of ADR 0232 redesigned with it. The layout
  of ADRs 0262 to 0265 stays.
- Reading through a view named after the block instance. The generated data
  hooks and block clients still read the block table (ADR 0392).
- PowerSync streams for a child table joined to an app parent subject, and
  attachment streams scoped beyond the view's `where` (ADR 0392).
- The owned-column default flip (ADR 0373). It needs a migration note and runs
  after the renames, as ADR 0373 says.
- Inferring the notifications block's settings and the `standardSchema` settings
  from the schema files and the Standard Schema setup, beyond the cascade of ADR
  0370 and the json columns of ADR 0371.
- The drive `grants` mode.

### Outside this repository

The cloud app's `/create` design URLs that were already shared still carry the
`integrations` field. The library reads `adapters` (ADR 0386), so the cloud app
has to write `adapters` and accept the old field when it reads a URL. A design
file written by `init` already uses the new name.

## Alternatives considered

Renaming `rank` to `ratings` would have matched the noun rule of ADR 0130 but
moved the meaning of the word away from reviews, scores and votes. Keeping the
publication in a migration and exempting it from the coverage check was
rejected: the check is the promise of ADR 0390, and the Supabase CLI has no
exemption list for publications.

## Consequences

The migration guide lists the manual steps (`organization` to `auth.tenant`,
the cloud app URLs). The deferred items stay visible here, in the pull request
and in the changeset. A table dropped from `gen.powersync.instances` leaves the
declared publication shorter than the migrated one until a migration removes it;
`powersync streams` writes no `drop` migration.
