---
"better-supabase": minor
---

Adds `better-supabase db squash`, which replaces the migrations with one baseline of the declarative schema and carries over the module extensions and the data migrations `--keep` names, and the `tooling.env.map` config key, which adds variables under the names your app reads to what `dev env` and `dev run` set.
