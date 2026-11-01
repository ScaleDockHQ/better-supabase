# Setup and authentication

> Verified against Vercel AI Gateway docs (getting-started updated 2026-10-02) and Vercel CLI docs, 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/getting-started>, `/authentication-and-byok`, `/authentication-and-byok/api-keys`, `/authentication-and-byok/oidc`, `/authentication-and-byok/byok`, `/pricing`. Append `.md` or send `Accept: text/markdown` for the markdown form.

## Tiers

Every team gets a free tier (a subset of models, a monthly included credit that starts at the first request, lower per-model rate limits) and a paid tier that starts when you purchase AI Gateway Credits (all models, no AI Gateway rate limits, provider limits still apply). Token rates follow provider list prices with no markup and no platform fee, including with BYOK. Some capabilities carry add-on charges (custom reporting, team-wide provider allowlist, team-wide ZDR, trace drains); read `/pricing` for current figures and ask before enabling any.

## API keys

Keys belong to a Vercel team and work locally, in CI, on external servers and on Vercel.

```bash
vercel ai-gateway api-keys create --name my-api-key --limit 10 --refresh-period monthly
vercel ai-gateway api-keys list
vercel ai-gateway api-keys inspect <key_id>
```

The key value is shown once. Store it immediately:

```bash
umask 077; read -r -s -p "AI Gateway key: " k; printf '%s' "$k" > ~/.config/ai-gateway-key; unset k
export AI_GATEWAY_API_KEY="$(cat ~/.config/ai-gateway-key)"
```

API alternative: `POST https://api.vercel.com/v1/api-keys?teamId=$VERCEL_TEAM_ID` with a Vercel access token and body `{"purpose":"ai-gateway","name":"..."}`; optional `projectId`, `expiresAt` (ms epoch), `metadata.spendAttribution`. The response field `apiKeyString` is the secret. Create keys with the CLI scope you intend (`vercel whoami`, `vercel switch`, `--scope <team>`).

**Spend attribution:** a key counts toward either a member (**User**, also counts toward the team budget) or the **Team** only. New dashboard keys default to User. Only team Owners and AI Gateway Budget Managers can change attribution (per the docs). When a member leaves, their keys are deactivated.

## OIDC on Vercel

Deployments can skip keys: Vercel injects an OIDC token tied to the project. Locally run `vercel link` then `vercel env pull`; the token lasts 12 hours, so pull again when it expires. The AI SDK picks up OIDC when `AI_GATEWAY_API_KEY` is unset. For raw HTTP clients send `VERCEL_OIDC_TOKEN` as the bearer token. OIDC spend counts toward team and project budgets.

## BYOK

Dashboard: AI Gateway > Bring Your Own Key, choose a provider, add credentials, keep **Enabled** on, **Test Key**. Credentials are team-wide. Requires the paid tier. If a call with your credentials fails, the gateway retries with system credentials, billed to credits (with ZDR on, only ZDR-eligible system credentials are used). BYOK spend is not counted in budgets.

Request-scoped BYOK passes credentials per call with `providerOptions.gateway.byok` (for example `{"anthropic":[{"apiKey":"..."}]}`), which ignores dashboard-cached BYOK for that request. Read the key from an environment variable, never inline.
