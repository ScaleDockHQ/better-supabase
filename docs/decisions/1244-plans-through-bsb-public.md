# 1244: Read the plan catalog through `bsb.public()`

- Status: accepted
- Date: 2026-11-25

## Context

`getPlans` in the sample read `public.plans` and `public.plan_features` with
`bsb.admin()`, the service role. The catalog is the same for every visitor, so
the entry was shared, but the read skipped RLS. The cache tier rules say a
shared read runs under RLS, never as the service role.

## Decision

Both tables get an `anon` select grant and a select policy for `anon` and
`authenticated` (`20270120010074_plans_public_read.sql`, generated from
`supabase/schemas`). `getPlans` calls `bsb.public({ tables: ["plans",
"planFeatures"] })`, which reads as `anon` and tags the entry with both tables.
Doctor BS645 passes because `anon` can select both.

## Alternatives considered

- Keeping `bsb.admin()`: no schema change, but the read bypasses RLS.
- `bsb.kept` with `share: "public"`: also correct, and durable, but a plain
  `"use cache"` entry is enough for a catalog that changes outside the app.

## Consequences

The plan catalog is readable by anonymous clients through PostgREST. It holds
plan names, prices and feature flags that the pricing page already shows.
