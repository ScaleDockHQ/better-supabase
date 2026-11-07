# 0323: Gate the config type-check on a provider key union

## Status

Accepted

## Context

`defineConfig` checks every permission key in `blocks.<block>.permissions`, `blocks.permissions.roles` and `subjects.<type>.permissions` against the keys of a typed `AuthorizationProvider<Key>`. The union is the one part of the config's types that grows with the app: a large provider lists hundreds of keys. The type benchmark measured only the generated client, so growth in the config's check time went unseen.

## Decision

The type benchmark in `tests/types/perf` gains a `config` program: a provider with 300 keys, 40 subjects that name keys, 20 roles that list 15 keys each and a block that remaps an action. Types and instantiations are gated per compiler (TypeScript 6, 7 and 7.1) within the 10% tolerance of the other profiles, against the numbers in `baseline.json`. The default `block.action` to `resource.action` mapping is unchanged (ADR 0260) and needs no type.

## Consequences

A change that widens the permission types shows up in `typecheck:perf` before it reaches an app. The current numbers are 17,260 instantiations for the program on all three compilers.
