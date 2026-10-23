---
"better-supabase": minor
---

Record sections become record bindings. A block declares one `record` binding,
named by its key in the config, and `gen` writes one `records/<type>.ts` per
record type instead of the `features/` folder, the navigation and the command
files. `bsb.record(type)` replaces `recordServer` and `bsb.sectionAction`, and
`gen.recordTypes` replaces `gen.generateFeatures`. `better-supabase codemod 0.15`
renames the section exports and lists the calls to move.
