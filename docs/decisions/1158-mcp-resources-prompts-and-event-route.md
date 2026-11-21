# 1158: Add MCP resources, prompts and an event route

- Status: accepted
- Date: 2026-11-21

## Context

`@ai-sdk/mcp` 2.0.102 has client methods for resources and prompts and exports
`experimental_createMCPEventWebhook` (only under the `experimental_` name) and
`Experimental_MCPEventStore`. `postgresMcpEventStore` already keeps the event
state in Vault.

## Decision

`mcpResourceTools` lets the model read only URIs the server listed, cuts text at
`maxChars` and reports binary by size. `mcpPrompts` and `mcpPromptMessages`
return an `AsyncResult`. `mcpEventRoute` wraps the SDK webhook and adds the
`claim` dedupe. No new SQL.

## Alternatives considered

Exposing every resource URI to the model: rejected, a model could read
unlisted URIs.

## Consequences

The `experimental_` import alias must be revisited when the SDK renames it.
