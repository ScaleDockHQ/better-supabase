---
"better-supabase": minor
---

`defineApi` publishes every table and every block instance by default. Without `resources`, each table gets its CRUD operations; a map now publishes only the tables it names, and `resources: false` publishes none. Each table also gets the contract verbs `page`, `count`, `aggregate` and `upsert` as `POST /<table>/<verb>` (operation ids such as `countCustomers`), served by `defineResource`, `bsb.resource` and `bsb.resources` too; `verbs` limits them, and a write hook drops `upsert`. Each block instance gets `POST /<instance>/<method>` per client method, configured with the new `blocks` option (`verbs`, `path`, `tag`, `permissions`).

`createOrpc(betterSupabase).router(api, { guard, meta })` serves that model as oRPC procedures, with routes that match the document. `bsb.blockRouter` is removed: serve `bsb.router(defineApi(betterSupabase, options))` instead. Doctor reports BS418 for a `blockRouter` call that is left.
