# 0035: A structural Flags SDK adapter, and custom contexts instead of brands

- Status: accepted
- Date: 2026-10-17

## Context

Apps on Next.js declare flags with the Vercel Flags SDK (`flags`), which
precomputes flags in the proxy and lists them in Flags Explorer. The flags
block already evaluates flags in Postgres (`flag_enabled()`) and in an
OpenFeature provider with the same rules, so an adapter only has to put the
SDK's `Adapter` contract over that provider.

Apps also need to target flags by something other than a tenant or a user.
A white-label product such as Centrakit serves several brands, and wants a
flag on for one brand. better-supabase has no brand concept; brands live in
the app.

## Decision

`better-supabase/flags-sdk` implements the Flags SDK `Adapter` shape as a
structural type and never imports `flags` (ADR 0009). `flags` is an optional
peer with a type test against the real `Adapter` (ADR 0036). The adapter
evaluates with the block's `evaluateFlag` over the provider's cached
definitions, falls back to the declaration's `defaultValue` when a flag is
missing or fails to load, and shares one cache and one `adapterId` across
every flag so `evaluate()` decides them in one batch. `createIdentify`
returns entities named as Vercel Flags targets them (`user`,
`organization`, then each custom context at the top level, such as
`brand`), so one `identify` serves this adapter and `vercelAdapter`.

Brand-like targeting is a generic custom context. `blocks.flags.options.contexts`
names each context and the table and column that hold a tenant's value.
Rules gain `contexts`, overrides gain `context` and `context_key`, and
`flag_evaluation()` reads a missing context value from the tenant. The flags
module moves to version 3 with an upgrade from version 2, and the
TypeScript evaluator mirrors it. Flags also gain `description` and
`archived`, which Flags Explorer shows and hides.

## Alternatives considered

A first-class `brands` table would fit Centrakit and nobody else, and every
other dimension (region, channel, partner) would need its own. Tenant
parents (an organization hierarchy) are a different feature: memberships,
billing and settings inherit down the tree. They need their own ADR, and a
parent can become a custom context once they exist. Importing `flags` would
make it a dependency of every app (invariant 1). Nesting custom contexts
under one `contexts` entity would break the entity paths Vercel Flags
targets, so they sit at the top level.

In 0.32 the adapter follows the Flags SDK's own adapters:
`betterSupabaseAdapter` is a ready adapter read from the environment on
first use, `createBetterSupabaseAdapter` builds one over a project or a
transport and carries `identify`, and `createIdentify({ server })` reads the
session the way the server does, without refreshing it. Refreshing stays in
the proxy (invariant 7), so there is no auth-cookie flag.

## Consequences

An app declares its contexts in config and passes their values through
`identify`; policies read them from the tenant without extra arguments. The
OpenFeature provider and the adapter don't read the tenant table, so a rule
on a context only matches in the app when `identify` or `flagContext`
supplies the value. A breaking `flags` release fails the type test before
the peer range widens.
