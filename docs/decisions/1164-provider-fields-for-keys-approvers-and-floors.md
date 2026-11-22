# 1164: Read keys, approvers, managed users and approval floors from the authorization provider

- Status: accepted
- Date: 2026-11-22

## Context

An app that wires leave, expenses and time entries repeated three kinds of fact in `better-supabase.config.ts`: the permission key of each block, the function that decides who approves, and the approval floor of each operation. The provider already owns the keys and the policy functions, so the config stated them twice and the two copies drifted.

## Decision

`AuthorizationProvider` gains optional fields: `actionKeys` (blocks, record types, buckets, topics), `functions.approverFor` and `functions.managedUsers`, and `operations["<subjectType>:<action>"].approval`. The config entry (`blocks.<name>.permissions`, `options.decider`, `options.policies`) still wins, so a provider that sets none keeps working and `apiVersion` stays 1 because every addition is optional. `gen sql` and doctor BS411 check these keys the way they check module keys. `codemod config --prune` removes a `permissions` entry equal to the provider's key. `options.decider` is dropped by hand, because the codemod cannot show that the function does the same.

## Alternatives considered

A new `apiVersion: 2` would force every provider adapter to change for fields most apps do not use. Reading the keys from the database at render time was rejected because `gen` must render offline.

## Consequences

The config shrinks by the keys and floors an app repeated. Provider authors own more of the contract and must keep `sqlComplete: true` honest. Revisit when a field becomes required.
