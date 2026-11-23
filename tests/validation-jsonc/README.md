# validation-jsonc

A project with no `config.toml`: `supabase/config.jsonc` is its only Supabase
config, as after `supabase config convert --format jsonc`. The tests hold
`upgrade` to writing the module files into the declarative schema folder the
config names, and `doctor` to finding no config problem (BS711) and no pg-delta
migration warning (BS316).

```sh
pnpm test
```
