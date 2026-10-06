---
"better-supabase": minor
---

`better-supabase gen --metadata <path|->` generates from a `GeneratorMetadata` document instead of the database, so it runs as an out-of-process generator for `@supabase/typegen`. `-` reads the document from stdin. It prints one file on stdout and every notice on stderr; `--emit schema|types|zod|valibot|json-schema` picks the file (default `schema`, the `defineSchema` module with its metadata written into it), and `--out <dir>` writes the usual files into a directory instead. It exits 65 with the reason on stderr when it can't read the document, the document is not JSON, its `version` is not the `GENERATOR_METADATA_VERSION` the pinned `@supabase/postgrest-typegen` writes, or the schema rejects it.

The document has no policies, grants, indexes, triggers, buckets, realtime publication, foreign key actions or multi-column constraints, so relations, enums, single-column unique keys and single-column CHECK unions stay typed, and a notice names what a database connection would add. `doctor --metadata` checks the same document and skips the checks that need what it lacks with an info finding. The `gen` docs show the `externalLanguage` entry that registers the command in `@supabase/typegen`, and a new roadmap page at `/docs/roadmap` lists what is planned now, next and later, including the blocks the blocks overview listed as missing.
