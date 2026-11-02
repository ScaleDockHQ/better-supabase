---
"better-supabase": minor
---

Modules can declare tenant defaults in `BlockSql.seeds`, which render into an idempotent
`seed_<module>_defaults` function. `db seed --defaults` runs those functions for existing
organizations (`--tenant`, `--variant`, `--locale`), and `db seed --sample` applies generated sample
data from the Better Supabase cloud (`--demo-org`, `--size`, `--seed`, `--out`; needs a Pro plan).
The new `login`, `logout` and `whoami` commands manage the cloud login. `database.seed` gains
`defaults` and `sample` keys, and `better-supabase/sql` exports `seedDefaultsFunctions`.

The CLI refreshes an expired login through `POST /api/cli/auth/refresh` and saves
the rotated tokens, so `whoami` and `db seed --sample` keep working past the
access token's lifetime.
