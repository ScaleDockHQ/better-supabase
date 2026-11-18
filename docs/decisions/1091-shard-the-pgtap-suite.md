# 1091: Shard the pgTAP suite across three Schema jobs

- Status: accepted
- Date: 2026-11-18

## Context

The Schema job ran all 322 pgTAP files on one stack and took 4 to 20
minutes. The suite takes about 5 minutes on a normal run, but one scale file
(`scale_reactions_read` or `scale_attachments_read`) sometimes takes 7 to 10
minutes on its own, so the job was the longest check on every pull request
that touched `supabase/`. The unit duration map (ADR 0638) was missing 130
newer files, so the unit shards ranged from 5 to 11 minutes.

## Decision

- `database.yml` runs `Schema (1/3)` to `Schema (3/3)`, each on its own stack.
  `scripts/pgtap-shard.ts` packs the files by the durations in
  `scripts/pgtap-durations.json` with the same packing as the unit shards. A
  file without a recorded duration takes the median, so every file lands in
  exactly one shard. pg_prove runs with `--timer`, so the log holds the
  durations for a refresh.
- Only shard 1 checks the migration drift, the snapshot, the SQL lint and the
  advisors.
- A job named `Schema` needs the three shards and fails unless all passed, so
  branch protection keeps requiring one check.
- `packages/better-supabase/tests/unit-durations.json` is refreshed from the
  merged blob reports of two recent pull request runs.

## Alternatives considered

- More pgTAP shards. A shard spends about two minutes on setup and the slow
  scale file alone takes up to 10 minutes, so a fourth shard saves little and
  takes another runner.
- Running pg_prove with `--jobs` on one stack. The files share one database,
  and parallel files would contend on the same fixture rows.

## Consequences

The slowest Schema shard is bounded by the slow scale file when it hits, not
by the whole suite. Refresh `scripts/pgtap-durations.json` from the `--timer`
lines when a shard runs far longer than the others. The cause of the slow
scale file is not fixed here.
