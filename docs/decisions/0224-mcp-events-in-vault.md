# 0224: Keep MCP event subscriptions in Vault

- Status: accepted
- Date: 2026-11-03

## Context

The AI SDK's `MCPEventStore` holds a signing secret per subscription. A table readable by a browser would leak it.

## Decision

`postgresMcpEventStore` writes each subscription and an id index as Vault secrets, with no new SQL. `dedupeMcpEvents` runs a delivery once from an app-supplied `claim`.

## Consequences

No migration is needed. `update` is not atomic, so deliveries for one subscription run one at a time. Refresh before `refreshBefore` stays with the app until a pg_cron job exists (planned).
