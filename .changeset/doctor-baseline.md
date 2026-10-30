---
"better-supabase": minor
---

Doctor can accept the findings an existing project already has. Set `tooling.doctor.baseline` to a JSON file of `{ code, target, reason }` entries and run `doctor --update-baseline` to write it. Doctor then leaves those findings out and fails on an entry no finding matches, so the file only shrinks.

BS351 also reports writes through the typed client's repositories, such as `db.webhookEndpoints.create()`, on a table a block creates. The block clients (`db.webhooksOut`) are not reported.

At the root of a pnpm or npm workspace, the default `tooling.doctor.sources` now also scans `src/**/*.{ts,tsx}` in each package, so doctor sees the code of `apps/web` and the other workspace packages. A `sources` you set is used as it is.
