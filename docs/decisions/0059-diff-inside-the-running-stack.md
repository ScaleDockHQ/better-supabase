# 0059: Diff inside the running stack when the shadow database can't start

- Status: accepted
- Date: 2026-10-21

## Context

The CLI runs one local stack per checkout (ADR 0032), so a machine with a
few worktrees runs many postmasters. Every postmaster keeps one System V
shared memory segment, a 56-byte interlock, even with `shared_memory_type =
mmap` and `dynamic_shared_memory_type = posix`, which are already the
defaults. macOS allows 32 segments (`kern.sysv.shmmni`), and raising the
limit needs a boot argument the app can't set.

`supabase db diff` and `supabase db schema declarative sync` start a shadow
database, another postmaster. On a machine with 31 segments in use it fails
with "could not create shared memory segment: No space left on device", and
the schema workflow stops. Stopped stacks keep their data, and stacks for
deleted worktrees or branches linger until someone removes them.

## Decision

Three pieces, all in the CLI:

- `better-supabase stack ls` lists the stacks the Supabase CLI manages with
  their branch, worktree, state and segments, and `stack prune` destroys
  stacks whose worktree or branch is gone (and stops idle ones with
  `--stop-idle`). The stack id comes from the postmaster's `-D` data
  directory (`src/cli/stacks.ts`, `src/cli/shm.ts`).
- Doctor BS700 warns when 80% of the segments are in use and names the
  stacks that hold them; BS701 flags a stack that keeps its buffers in
  System V memory (`src/cli/doctor/stacks.ts`).
- `better-supabase db diff` runs the Supabase CLI's command and, when the
  shadow database can't start (or with `--in-stack`), diffs inside the
  running stack: it copies the schema into a temporary database with
  `pg_dump` and `psql`, replaces the objects the declarative files manage
  with the files, and runs `supabase db diff --use-pg-delta --from local
--to <copy>` (`src/cli/in-stack-diff.ts`). The temporary database is
  always dropped.

## Alternatives considered

- Raise `kern.sysv.shmmni`. It needs a boot argument and SIP changes on
  macOS, and it only moves the limit.
- Set `shared_memory_type` in each stack. It already defaults to `mmap`;
  the interlock segment can't be turned off.
- Run the shadow database in the same postmaster as a database the Supabase
  CLI creates. That is the fix we asked the Supabase CLI for; until it ships,
  the in-stack copy does the same from outside.
- Apply the files to an empty database. The files reference platform
  objects (`auth.users`, `storage.objects`) that only a copy of the stack has.

## Consequences

The schema workflow keeps working with many worktrees. The in-stack diff
compares two databases rather than replaying migrations, so a migration it
writes starts with a comment that asks for review, and it refuses to run
when the stack has not applied every migration. It needs `pg_dump` and
`psql` from the stack's Postgres (found next to the postmaster, or
`$BSB_PG_BIN`). We revisit it when the Supabase CLI falls back without a
shadow postmaster and names System V exhaustion in its error.
