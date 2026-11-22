# 1154: Write a managed AGENTS.md block from init

- Status: accepted
- Date: 2026-11-21

## Context

Agents need a pointer to the skills, the docs MCP server and the rule against editing generated files.

## Decision

`init` writes a delimited block into `AGENTS.md` only when the project already shows agent files, and rewrites only what sits between the markers.

## Alternatives considered

Always creating `AGENTS.md`. Rejected: it adds a file to projects that don't use agents.

## Consequences

Idempotent on repeat runs; user text outside the markers is kept.
