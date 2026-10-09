---
"better-supabase": minor
---

`gen` writes tighter types from CHECK constraints, documents tables in the generated validators and can run from a metadata document. Run `better-supabase gen`.

- A nullable column a CHECK requires is typed not null, and `tables.<table>.insertOptional` marks columns the database fills on insert. `relations: { nullableUnderRls: true }` types to-one relations to RLS tables as nullable.
- `zod()`, `valibot()` and `jsonSchema()` add titles, descriptions and examples from comments, and enforce bounds from simple CHECK constraints.
- The generated module exports `WhereOf<"table">`, `OrderByOf<"table">` and `OrderTermOf<"table">`, and the metadata module is about 40% smaller.
- `gen --metadata <path|->` generates from a `GeneratorMetadata` document for `@supabase/typegen`, and `doctor --metadata` checks it.
- Generators declare `apiVersion: 1` and receive `model`. `gen` deletes files it no longer writes, fails on name collisions, and `gen --watch` reloads the config and retries.
- **Breaking:** colliding `_by_` relations are named by every key column (`customerByCustomerOrganization`) instead of ending in `_`, and view copies are no longer relations. Keep an old name with `tables.<table>.relations`.
- **Breaking:** `@supabase/postgrest-typegen` is an optional peer; install it for `gen`, `introspect` and `doctor` with `pnpm add -D @supabase/postgrest-typegen@0.4.0`.
- **Breaking:** a `GeneratorInput` built by hand needs a `model`.
