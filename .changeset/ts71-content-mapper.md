---
"better-supabase": minor
---

TypeScript 7.1 can get the schema types from better-supabase's content mapper, so the repository no longer holds `database.types.ts` or the type half of `generated.ts`.

- `gen.contentMapper: true` turns on mapper mode. `gen` writes a `schema.bsb` marker and a `generated.ts` that keeps the runtime values and re-exports the types with `export type * from "./schema.bsb"`, and writes no `database.types.ts`. `Database` (the enriched one) now comes from `generated.ts`. Files mode stays the default, and its output is unchanged.
- `init --content-mapper` sets the option, adds `{ "package": "better-supabase", "extensions": [".bsb"] }` to `contentMappers` in `tsconfig.json` and adds `--runExternalCode` to the `typecheck` script. It prints the change instead when a file holds comments or has no such script.
- The mapper renders the same types `gen` writes in files mode, from the same config and snapshot, and caches them in `node_modules/.cache/better-supabase`; `gen` fills that cache, so the first `tsc` after it reads the types. It watches the config, the snapshot, `supabase/config.toml` and a stamp `gen` rewrites when the types change, so `gen --watch` reloads the editor. A failure becomes a diagnostic (BS603 to BS606) instead of stopping `tsc`, and a config or snapshot that fails to load keeps the last types.
- Doctor's new BS602 check reports a missing `contentMappers` entry, a TypeScript older than 7.1 and a `typecheck` script without `--runExternalCode`.
- The content mapper protocol version is pinned as `SPEC_PINS.typescriptContentMapper` (`"1"`).

Content mappers need TypeScript 7.1, which is in beta (`7.1.0-beta`). See the [content mapper](https://bettersupabase.com/docs/content-mapper) page and ADR 0097.
