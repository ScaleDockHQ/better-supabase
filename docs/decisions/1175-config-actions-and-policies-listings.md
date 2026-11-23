# 1175: List actions and access policies as data

- Status: accepted
- Date: 2026-11-22

## Context

A provider author who maps `actionKeys` has to guess which keys the app asks
for. The block keys came from `modulePermissionKeys`, but record types,
buckets and topics had no listing, and the keys a `@bsb access` tag turns into
policies existed only inside rendered SQL.

## Decision

`better-supabase config actions --json` and `listActions(config)` list every
block instance, record type, bucket and topic action with the key it resolves
to and its source: `config`, `provider` or `default`. `key` is `null` when
nothing names a key. A topic has the `receive` and `send` actions, which only
the provider can name, because the config holds no keys for topics.

`better-supabase config policies --json` and `listAccessPolicies(config,
comments)` list one row per policy a `@bsb access` tag renders. `accessBlock`
now builds those rows with `accessPolicies()` and renders the SQL from them, so
the listing and the SQL come from one function.

Both outputs carry `version: 1` and ship a JSON Schema. The functions are
exported from `better-supabase/sql`.

## Consequences

Provider authors can diff their `actionKeys` against the list. The rendered SQL
is unchanged. A change to the row shape needs a new `version`.
