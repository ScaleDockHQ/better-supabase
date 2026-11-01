# Troubleshooting

> Verified against Vercel AI Gateway docs (budgets, rate-limits, byok, api-keys), 2026-10-11

Sources: the pages under <https://vercel.com/docs/ai-gateway/>. Items marked inferred are consequences of documented behaviour.

| Symptom                                           | Cause and fix                                                                                                                                     |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 401                                               | Missing, revoked or wrong key; a departed member's keys are deactivated; OIDC token older than 12 hours (`vercel env pull`).                      |
| 402 `quota_for_entity_exceeded`                   | A budget in scope is exhausted: team, project, key or user. Message names the scope. Raise it or wait for the UTC reset.                          |
| Budget exceeded slightly                          | Soft cap: the crossing request completes.                                                                                                         |
| Project budget blocks, key works                  | Project budgets apply only to OIDC requests from that project; keys are never attributed to a project.                                            |
| 429                                               | Free-tier per-model limit, or upstream provider. Honor `retry-after`, back off, or buy credits for the paid tier.                                 |
| 403 on a model                                    | A team deny rule or model allowlist blocks it. `vercel ai-gateway rules list`.                                                                    |
| Unknown model                                     | Slug not in `GET /v1/models` or not available to your team (`?include_availability`).                                                             |
| Unexpected credit usage with BYOK                 | A BYOK call failed and fell back to system credentials. Check the log's billed-to field and key validity.                                         |
| BYOK spend not capped                             | By design; budgets do not count BYOK. Use provider-side limits.                                                                                   |
| Provider timeout has no effect                    | `providerTimeouts` apply to BYOK only.                                                                                                            |
| Claude Code asks to log in or ignores the gateway | `ANTHROPIC_API_KEY` must be empty and `ANTHROPIC_AUTH_TOKEN` set; remove a `model` override from `settings.json` if models look wrong (inferred). |
| `AI_GATEWAY_API_KEY` and OIDC both set            | The key wins over OIDC in the AI SDK (OIDC is used when the key is unset).                                                                        |
| Routing details missing in Logs                   | Routing attempt details are kept 30 days.                                                                                                         |
