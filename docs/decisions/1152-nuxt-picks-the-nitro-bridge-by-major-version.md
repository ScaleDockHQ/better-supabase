# 1152: The Nuxt module picks the Nitro bridge by major version

- Status: accepted
- Date: 2026-11-21

## Context

Nitro 3 uses h3 v2 and Nitro 2 uses h3 v1, and the module always wrote the v1 bridge.

## Decision

The module reads the Nitro major version from `nuxt.options._nitroMajor`, then `nuxt._nitro.meta.majorVersion`, and writes `toH3` for 3 and `toH3V1` otherwise. `better-supabase/h3` is the Nitro 3 entry, so no separate Nitro subpath is added.

## Alternatives considered

A new `better-supabase/nitro` subpath. Rejected: it would duplicate `h3`.

## Consequences

A Nitro 3 app needs no manual middleware.
