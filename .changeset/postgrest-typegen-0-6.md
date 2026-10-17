---
"better-supabase": minor
---

**Breaking:** the CLI uses `@supabase/postgrest-typegen` 0.6.0, and the optional peer now accepts `>=0.6.0 <0.7` instead of `>=0.4.0 <0.5`. Upgrade it with `pnpm add -D @supabase/postgrest-typegen@0.6.0`. `database.types.ts` again matches `supabase gen types` from Supabase CLI 2.121, which writes the same `ComputedFields` keys. View columns are typed with the nullability postgrest-typegen 0.6 reads from the view definition, so run `better-supabase gen` to regenerate.

The `GeneratorMetadata` type gains the optional `rpcFunctions` collection that postgrest-typegen 0.6 derives from `functions`, and the `RpcFunction` types it uses are exported next to it. Snapshots and `gen --metadata` leave it out, and the generator resolves it again from the ordered, stable functions of the generated schemas only.
