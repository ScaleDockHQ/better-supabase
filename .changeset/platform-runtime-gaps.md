---
"better-supabase": minor
---

`options.resolveAddress` of the notifications block names an app function that says where a member is reached on a channel, and deliveries, digests and bounce suppression use it. The Realtime triggers of `config.realtime.tables` and of block entities with `subject.realtime` are static `create trigger` statements in the schema file, so a schema diff sees them. `workflow_opt_outs` is an optional table. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`; delete a `track_realtime` call you wrote for a configured table.
