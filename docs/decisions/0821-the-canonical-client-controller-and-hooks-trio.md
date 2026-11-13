# 0821: The canonical client, controller and hooks trio

- Status: accepted
- Date: 2026-11-13

## Context

The audit counted 33 blocks with a `client.ts` and asked for the same client,
controller and hooks for every block (EX-1238). Those 33 files are bespoke UI
controllers (a slot picker, a checkout); a copy of one per block would be 190
files with nothing in them.

## Decision

The trio is the block's client (`create<Name>`), the generic `block-controller`
(`createBlockQuery`, `createBlockMutation`) and the hooks over it
(`useBlockQuery`, `useBlockMutation`, `useBlockEvent` and their Vue, Svelte and
Solid versions). The controller and the hooks take any client, so a block supplies
only its client. A bespoke `client.ts` stays for a block with its own UI state.

`tests/blocks/client-trio.test.ts` ratchets this: a block with an entity that
changes after it is created needs a `create`, except `credentials`,
`field-encryption` and `impersonation`, which are reached through
`vaultCredentials()`, the encrypting blocks' SQL and the support session. The
list can shrink; a stale entry fails the test.

## Alternatives considered

Generating a controller file per block would add 190 files that call the generic
controller. Writing clients for the three exceptions would duplicate
`vaultCredentials()` and the support session.

## Consequences

The documented shape is in `frontend/block-controllers.mdx`. EX-1238 is fixed with
three deliberate exceptions.
