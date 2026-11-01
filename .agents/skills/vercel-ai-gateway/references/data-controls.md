# Data controls, logs and observability

> Verified against Vercel AI Gateway docs (security-and-compliance, logs, pricing), 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/security-and-compliance>, `/security-and-compliance/zdr`, `/security-and-compliance/provider-allowlist`, `/observability-and-spend/logs`, `/observability-and-spend/trace-drains`.

## Retention

AI Gateway itself uses zero data retention by default: it permanently deletes prompts and responses after requests complete. Provider-level handling is separate, so for strict compliance enforce ZDR per request:

```ts
providerOptions: {
  gateway: {
    zeroDataRetention: true;
  }
}
```

With it, requests route only to providers with verified ZDR agreements (see the ZDR page for the list). Per-request ZDR has no extra cost on Pro and Enterprise; the team-wide default is a paid add-on. Disallow Prompt Training similarly restricts to providers that agree not to train on prompts.

## Allowlists

- Per request: `only: ['provider', ...]` in provider options, free.
- Team-wide provider allowlist (Pro and Enterprise, paid add-on) and model allowlist for team policy. Confirm plan and surcharge with the user first.

## Logs

Dashboard Logs show routing attempts, authentication input, inference region, ZDR status, cost and whether the request was billed to the gateway or BYOK. Date range up to 36 days back; routing attempt details are kept for 30 days. Programmatic access: `GET /v1/generation` for one generation.

## Trace drains

Forward OpenTelemetry traces of every request to your tool (Pro and Enterprise). They bill on separate meters outside credits and Pro has no allowance, so a high sampling rate raises cost. Pause or delete the drain to stop charges.
