---
"better-supabase": minor
---

`RemoteCacheKey`, which `bsb.remote()` and `bsb.sessionHandle()` return, has two new fields: `schema`, a hash of the generated schema meta, and `library`, the better-supabase version. A `bsb.kept()` key carries the version too. An entry filled before a migration and `gen`, or by another release, is then never read, also when Next.js's `experimental.durableUseCacheEntries` keeps `"use cache"` entries across deploys. Every remote and kept entry starts again once after the upgrade.

Doctor rule BS646 warns when `next.config` turns that flag on and the app fills shared entries with `bsb.public()` or the remote scope: their key doesn't follow the database's policies or the Supabase project. The Cache Components page has a new section on when to use the flag and when `bsb.kept()`, from `tests/next-durable-cache`, which builds the example with the flag and checks which reader reads the previous build's entry.
