# 0253: Name migrations by stamp and content hash

- Status: accepted
- Date: 2026-11-07
- Amends: 0250

## Context

`upgrade` wrote its block upgrade migration with the plain clock stamp, while
the extensions, data and module migrations moved the stamp past the newest name.
The Supabase CLI keys a migration by the digits before the first underscore, so
the plain stamp could share a version with a migration another tool wrote in the
same second, such as the authorization provider's generator. A command that was
run again could also write a second file with the same statements under a new
stamp.

## Decision

`migrationFile` in `src/cli/sql/migration-names.ts` names every migration the
CLI writes (`upgrade`, the extensions and data migrations, the migrations
workflow's module and read-sets files, the PowerSync publication and codemod
SQL). The stamp comes from `stampAfter`, which is later than every name in the
folder that starts with 14 digits. The hash is the first 8 hex digits of the
SHA-256 of the statements with comment lines and whitespace runs removed, and it
goes before `.sql`. A file with the same suffix and hash is reused, so a repeated
run writes nothing; `--force` passes `reuse: false` for a new file.
`hasMigrationSuffix` finds a migration by its suffix with or without the hash,
so migrations from earlier releases are still read.

## Alternatives considered

A sequence number in the name would collide across branches, and a random
suffix would make a repeated run write a new file every time.

## Consequences

Names are stable for the same statements and sort after every other tool's.
Doctor and `upgrade --check` read the newest module migration by suffix as
before. An app that matches names by `endsWith("_better_supabase_modules.sql")`
must match the optional hash too.
