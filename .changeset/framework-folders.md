---
"better-supabase": minor
---

The per-block framework subpaths go: `better-supabase/blocks/<block>/react`, `/vue`, `/svelte` and `/solid` (120 subpaths) and `better-supabase/chat-sdk/react`. A block's React hooks are now a registry item that shadcn copies into the app: `npx shadcn add @better-supabase/use-<block>` writes `hooks/use-<block>.ts`, with the same hook names, options and return values, and the app imports from `@/hooks/use-<block>`. Presets install the hook item with each block.

Vue, Svelte and Solid call `useBlockController(create<Name>Controller, options)` from `better-supabase/vue`, `better-supabase/svelte` or `better-supabase/solid`, with the controller from the block's main entry. It returns what the per-block hooks returned. `better-supabase/react` now exports `useController`, `useLatest`, `useBlockEnv` and `useBlockTenant` for your own hooks, and `better-supabase/blocks` exports `envBlockOptions`, `envBlockSettings` and the `BlockEnv` type.

Doctor's BS418 finds imports of the removed subpaths and names the registry item.
