---
"better-supabase": minor
---

`gen.serverBlocks` writes `blocks.<name>.ts` with `<name>Instances` and `<name>Blocks`, a `defineBlocks` over only the instances you list, so a route that builds its server from the set bundles those blocks and not the rest of `blocks.generated.ts`. `gen` fails when a listed block requires a port no listed block provides. On the Next.js example the sign-in page, the customers API and the customers page lose 48, 54 and 50 percent of their server chunks. The key is optional and off by default: `better-supabase upgrade` rewrites no module, `gen` writes nothing new without it, and no data moves.
