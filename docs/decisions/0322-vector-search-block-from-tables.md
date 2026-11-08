# 0322: Install vector-search from the tables that use it

## Status

Accepted

## Context

An app with a `vectorSearch` table had to add `vector-search` to `blocks` as well, though the block has no other purpose.

## Decision

Config resolution adds `vector-search` to the blocks when `vectorSearch` has a table, and so does the table-tag pass for a `vector-search` tag. A `blocks` entry stays valid and is the place for the `schema` option.

## Consequences

The line disappears from app configs. An app without a vector table renders no vector SQL, as before.
