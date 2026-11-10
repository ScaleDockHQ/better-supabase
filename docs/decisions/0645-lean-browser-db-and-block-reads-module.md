# 0645: Give the browser a lean db and write the block reads to their own module

- Status: accepted
- Date: 2026-11-10
- Amends: 0635, 0636

## Context

ADR 0635 split the connection runtime from the definition class and left `react` plus `query` at
43 KB gzip, short of the 30 KB target: the browser client builds a `db`, and that `db` carried
read-set batching, vector search, call statistics and the decode helper whether or not a page
called them. ADR 0636 left the chat routes, the pipeline overview and the banking overview on the
full block set, because a read set was bound to the full `betterSupabase` and to the `reads`
object in `blocks.generated.ts`, which imports every block.

## Decision

- `core/define-runtime.ts` builds the core `db`: repositories, `$rpc`, `$run`, `$table`, `$with`,
  `$withoutPlugins`, `$storage` and `$buckets`. `core/define-extras.ts` adds `$many`,
  `$decodeReadSet`, `$search`, `$stats` and `$decode`, plus the stats recorder. The entries that
  connect a server, an adapter, the native client or the testing helpers call
  `provideConnectionRuntime()` from `core/define-runtime-full.ts`, which installs both. Only
  `client/bind.ts` calls `provideLeanConnectionRuntime()`, so the browser bundle never imports the
  extras.
- The types follow the runtime. `Db` is `CoreDb` plus `DbExtraHelpers`, and `client.db` is a
  `CoreDb` without the extras, so a removed call fails at type-check time. `BetterClient` takes the
  helpers as a type parameter, and `createNativeClient` is a function that installs the full
  runtime and returns the full type, because the offline engine batches reads through `$many`.
- A filter tree in `where` (`FilterQuery`) reaches the query builder through a slot
  (`ir/filter-slot.ts`). The converter and its field checks (`ir/filter-tree.ts`, 16 KB raw) load
  with the full runtime, or with `enableFilterTrees()` from `better-supabase/list`. A read with a
  tree before that fails with a message that names the call.
- `createClient` validates the URL and the publishable key with `parsePublicEnv`
  (`env/public.ts`), not the full `parseEnv`, which also reads the server settings (7 KB raw).
- `gen` writes `reads` and the types of its arguments and results to `blocks.reads.ts`, which
  imports only `blockRead`. `blocks.generated.ts` re-exports it, so existing imports keep working.
  `defineReadSet` already accepted any app, with or without blocks; a test now holds that for an
  app built from a block set.
- In the example, the read sets are built over `app` and the `reads` of `blocks.reads.ts`. The
  pipeline and banking overview routes build their server from `gen.serverBlocks.core`, and the
  chat and durable chat routes (and the AI telemetry they share) from `gen.serverBlocks.shell`,
  which `assistant-server.ts` already imported.

## Measured

Library code only, min+gzip, supabase-js external (`tests/bundle/baseline-shipped.json`):

| Consumer                                 | Before | After  |
| ---------------------------------------- | ------ | ------ |
| react + query                            | 43,060 | 35,444 |
| saas client with blocks                  | 63,616 | 55,954 |
| next proxy                               | 27,088 | 24,018 |
| next + client                            | 93,429 | 94,316 |
| hono                                     | 71,973 | 72,174 |
| client/native + react/native + powersync | 46,940 | 47,229 |

By step, `react + query`: the extras split 43,207 to 39,648 raw-measured in the analyzer, the
public env parser to 38,708, and the filter-tree slot to 35,580. The consumers that connect a
server pay 0.2 to 0.9 KB for the second module.

`tests/next-build` from a fresh `next build` of this branch against `origin/main`:

- First-load JavaScript of the `(app)` pages falls by about 26 KB raw and 8 KB gzip (for example
  `/appraisals`: 1,467,108 to 1,441,007 raw, 454,362 to 446,270 gzip).
- `/api/pipelines/[id]/overview` and `/api/banking/[id]/overview`: 2,320,170 to 1,049,586 raw,
  700,997 to 330,241 gzip, 584,901 to 287,326 brotli (-54.8%).
- `/api/chat` routes: 2,855,059 to 1,737,797 raw, 845,482 to 526,375 gzip (-37.7%).
- `/api/chat/durable` routes: 4,459,112 to 3,344,605 raw, 1,332,068 to 1,014,397 gzip (-23.8%).
- The proxy: 1,235,283 to 1,232,456 raw.
- Every other server entry grows by 0.1 to 1.0 KB raw (the second runtime module and the filter
  slot), under 0.5 KB gzip. That is more than the 512 byte slack of the server check, so the server
  baseline is written fresh from this build instead of lowered by `update`.

## Not done

- 30 KB for `react + query`. What remains is the executor (`compile/postgrest.ts`,
  `core/postgrest-executor.ts`, `core/in-chunks.ts`), the query builder (`ir/build.ts`), the
  repository methods and the error mapping, about 86 KB raw minified, each of which the browser's
  `list`, `get`, `create`, `update` and `delete` need. Splitting the repository by method, or the
  data-only definition with free functions (`spec`, `cache`, `tablesOf`) the plan describes, cuts
  under 1 KB gzip (`define.ts` measured at 0.9 KB raw-gzip) for a rename of 237 call sites, so it is
  not done.
- The chat routes stay on the shell set rather than a set of their own: they read no block, but
  `assistant-server.ts` and `knowledge-server.ts` already build the shell server, and a second
  server would add a session memo to the same route.
- `tests/validation-presets` wiring files keep their old shape until the integration run rewrites
  them; the old `reads` import still works.

After merging main the baselines are re-measured from a fresh build of this branch with the `update`
scripts: `tests/next-build/server-baseline.json` rises for 201 entries (raw up to about 700 bytes,
the second runtime module and the filter slot), First Load JS and the bundle baselines are lowered
or re-recorded, and the shipped sizes of `react + query`, `saas client with blocks` and `next proxy`
drop as the table above shows. The guard in `next-build.test.ts` is unchanged.
