# 0994: Theme the React Flow attribution with the editor tokens

- Status: accepted
- Date: 2026-11-14

## Context

A browser check in dark mode after a reload (finding EX-212) showed the
canvas edges, the minimap and the controls following the theme, but the React
Flow attribution link still drew light text on a translucent white box.

## Decision

`globals.css` sets the attribution's background and colour from the card and
muted-foreground tokens, next to the other `--xy-*` overrides. The attribution
stays visible.

## Alternatives considered

`proOptions.hideAttribution`: React Flow asks that the credit stay unless the
project subscribes.

## Consequences

The edges render after a hydration reload in both themes; the check was done
with `agent-browser --session x6b` on a template workflow.
