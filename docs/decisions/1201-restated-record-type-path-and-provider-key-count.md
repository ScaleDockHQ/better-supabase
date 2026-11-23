# 1201: Report record type keys under recordTypes, and count the keys a provider could supply

- Status: accepted
- Date: 2026-11-22

## Context

`restatedEntries` named a record type permission that equals the provider's
`actionKeys` as `subjects.<type>.permissions.<action>`. `subjects` is the
resolved registry; the config key is `recordTypes`. BS427 pointed at a path no
config file holds, so `codemod config --prune` could not find it and the
baseline target never matched the key the app writes. Separately, nothing told
an app how many of its action keys the provider could carry instead.

## Decision

- The restated path is `recordTypes.<type>.permissions.<action>`. A baseline
  entry for the old `subjects.<type>...` target is stale; `codemod
  doctor-baseline` regenerates it.
- BS715 (info) counts, under the provider access model, the action keys the
  config writes next to the keys `actionKeys` supplies, by kind, using
  `listActions` (ADR 1175). It names `config actions --json` for the list. It
  is silent without a provider, outside the provider model, and when the config
  writes no key. A key equal to the provider's stays BS427.

## Alternatives considered

- Fold the count into BS427: the entries there are removable, and the count is
  not.
- A warning: moving keys is a choice, and a large app would carry the finding
  for as long as it keeps them.

## Consequences

Doctor output for a restated record type changes its target text. The code
number is provisional and may move when other streams add rules.
