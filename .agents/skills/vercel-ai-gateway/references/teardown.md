# Teardown

> Verified against Vercel AI Gateway docs and Vercel CLI docs, 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/authentication-and-byok/api-keys>, `/observability-and-spend/budgets`, `/models-and-providers/routing-rules`, `/pricing`.

Nothing bills by the hour, but keys, credits, add-ons and trace drains persist. Ask before each deletion.

- [ ] List: `vercel ai-gateway api-keys list`, `vercel ai-gateway budgets list`, `vercel ai-gateway rules list`.
- [ ] Delete test or contractor keys in the dashboard (API Keys page, key menu) or via the Vercel API; deleting or revoking is immediate. Check the CLI help for a delete subcommand in your version (`vercel ai-gateway api-keys --help`).
- [ ] Remove budgets you created for a test: `vercel ai-gateway budgets remove <scope> [name]` (and `--default` for defaults). Removing a default lifts that cap from everything it covered.
- [ ] Remove routing rules: `vercel ai-gateway rules remove <rule_id>`. Rewrites and denies affect the whole team.
- [ ] Remove BYOK credentials (dashboard BYOK page) when no longer needed, or turn off **Enabled**.
- [ ] Turn off paid add-ons you tried: team-wide ZDR, provider allowlist, custom reporting; pause or delete trace drains.
- [ ] Undo client config: remove `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` and the Keychain entry written by `vercel ai-gateway setup`, and restore `~/.claude/settings.json`.
- [ ] Verify: old key returns 401, `vercel ai-gateway api-keys list` is as expected, `GET /v1/credits` balance is stable.
