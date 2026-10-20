# 0049: Serve the CLI as a stdio MCP server, with consent for writes

- Status: accepted
- Date: 2026-10-19

## Context

Coding agents already run the CLI through a shell and read its JSON
envelope (ADR 0045, ADR 0047). Agents that speak MCP prefer tools with input
schemas they can list, and some can't run a shell at all. `createMcp` serves
an app's data over Streamable HTTP as the signed-in user, which is the wrong
shape for development: there is no user, and the tools are the CLI's
commands. The JSON-RPC handling for `initialize`, `server/discover`,
`tools/list` and `tools/call` lived inside `createMcp`, tied to `Request`
and `Response`.

## Decision

The transport-free part of MCP moves to `src/mcp/protocol.ts`: the protocol
versions, the tool and result shapes, the handshake results and
`answerMessage`, which answers one JSON-RPC message for a `ProtocolServer`.
It imports nothing from Node. `createMcp` keeps its HTTP checks and uses the
shared results; the `better-supabase/mcp` entry exports `answerMessage`,
`answerLine` and the `ProtocolServer` type.

`better-supabase mcp` serves a fixed set of tools on stdio, one message per
line. Each tool maps its arguments to one command line and calls `run()` in
process with `--json`, so output is captured and the tool returns the result
envelope as `structuredContent`. The read-only tools run by default.
`--allow-writes` adds `gen`, `sql_sync`, `apply` and `add`. A write tool
first returns a `consent_required` error with a token computed by
`consentToken` over the command line, and runs only when the next call
passes that token as `confirm`. The inner command runs with `--agent no`,
so the MCP consent is the only one.

`createMcp` logs one warning naming the tools that a missing authorizer
hides, since a tool with a `permission` and no authorizer never lists.

## Alternatives considered

Building the server on `@modelcontextprotocol/sdk` would add a dependency
the CLI inlines (ADR 0007) for four methods. Exposing every command as a
tool gives an agent `seed --apply` and `--force`, which write to the
database or overwrite files the user owns; the fixed list leaves them out.
Spawning a child process per call isolates commands, but costs a Node start
per call and loses nothing the in-process `run()` doesn't already capture.

## Consequences

An agent gets the CLI's tools with schemas and the same envelopes as the
shell, and can't write a file without a token the user saw. The tool list is
hand-maintained next to the manifest, so a new command needs a tool entry to
appear. Commands run sequentially, one message at a time, so a slow `doctor`
holds later calls.
