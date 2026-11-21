# 1155: Vercel packages 8 and 11: what was built and what was not

- Status: accepted
- Date: 2026-11-21

## Context

ADR 1151 left these items open. They were checked against the installed packages.

## Decision

Built: the Nuxt Nitro 3 path, `blobUploadRoute`, the `init` AGENTS.md block and the Vercel MCP recipe. Skills already publish: `npx skills add ScaleDockHQ/better-supabase` works from the repo's skills folder. Not built: wildcard domains (the Vercel domains API for wildcards needs nameserver delegation that the SDK does not expose, unverified); a Nitro subpath (see 1152); the Astro session driver and route cache provider (the interfaces exist in Astro 7.4.11, but they need new subpaths and a SQL store and were not verified end to end); shipping the docs in the package (they are 8.1 MB, 1.9 MB gzipped, against a 7.2 MB package, so the version-matched docs stay on the MCP server and llms.txt); media routes, MCP resources and prompts from `connectTools`, the MCP event webhook, the HarnessAgent route, the steering queue, tenant tool context and tool guardrails (each needs a new SQL store or an SDK surface not confirmed against the installed AI SDK).

## Alternatives considered

Building the unverified items from the plan's wording. Rejected: the plan marks them confirm first.

## Consequences

These items stay open for a separate change with their own ADRs.
