---
"better-supabase": minor
---

Blocks install as instances. Each key in `blocks` names an instance; a key
other than a block's name installs a second instance of the block in its
`block` setting, `on` lists the record types an attachable block attaches
to, and `uses` picks the instance of a dependency. The options of a named
instance are typed from its block. `resolveConfig` reports unknown blocks,
renamed or repeated core blocks, unknown `uses` keys and a missing `uses`
together, and `ResolvedConfig.instances` lists the resolved instances. The
config JSON schema accepts instance keys.
