# 1165: Make blocks a list of names and entries

- Status: accepted
- Date: 2026-11-22

## Context

`blocks` was an object keyed by block name. A block with nothing to configure still took `{}`, and installing one block twice needed a `block` key under an invented name, so the common case was noisy and the rare case was awkward.

## Decision

`blocks` is a list of block names and `{ block, name?, ...entry }` objects. The object form is rejected when the config loads, with a hint to run `better-supabase codemod blocks-list`, which keeps comments and key order. The resolved config keeps its keyed shape internally, so every renderer reads the same data. A `name` is only needed for a second instance.

## Alternatives considered

Accepting both forms was rejected: two shapes double the docs, the schema and the tests, and 0.82 is the release that can break. Keeping the object and adding an `instances` key was rejected because it leaves the empty `{}` entries.

## Consequences

Configs read shorter and a repeated block is first class. Every config must run the codemod once. Revisit if the list form hides ordering that the object form made explicit.
