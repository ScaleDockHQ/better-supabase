# Regression evals in CI

> Verified against promptfoo 0.124.1 docs (CI/CD, GitHub Action, CLI exit codes), 2026-10-11

Run a fast eval on every change that can affect model behaviour (prompts, system prompts, tool schemas, model IDs, gateway routing, quantization), and a full eval on a schedule or before release. Tool mechanics (workflow YAML, action inputs, flags, exit codes) live in the promptfoo skill: `npx skills add ScaleDockHQ/llm-skills --skill promptfoo`, references `ci.md` and `combos/quant-ci-gate.md`, template `llm-evals.yml`.

## Two tiers

| Tier    | Trigger                                                    | Set                                          | Budget    |
| ------- | ---------------------------------------------------------- | -------------------------------------------- | --------- |
| PR gate | `pull_request` touching prompts, eval config, model config | 20–100 deterministic items, `critical` first | Minutes   |
| Full    | nightly `schedule`, release tag, or manual                 | Full golden set, judges allowed              | As needed |

Keep the PR gate deterministic (`contains`, `regex`, `is-json`, tool-call checks). Model-graded assertions add cost and variance; reserve them for the full tier unless the judge is calibrated (`llm-as-judge.md`).

## What the gate enforces

- The build fails on promptfoo's exit code: `100` for failed tests or a pass rate below `PROMPTFOO_PASS_RATE_THRESHOLD` (default 100), `1` for other errors. No extra gate script is needed for a simple rule.
- PR tier: threshold 100 on the `critical` items. Full tier: a lower threshold only for failures you have recorded as known and accepted.
- Numerics changes (quantization, KV dtype, engine upgrade) need the A/B gate in `quality-gates.md`, not only a regression run: two endpoints, noise floor, per-item flips, decision record.

## Policy for private endpoints and data

- **Self-hosted runner** when the endpoint is only reachable on a private network (for example a LiteLLM gateway on `10.0.0.1`). Do not expose an inference endpoint to the internet just for CI.
- **Secrets** in CI secrets, base URLs in variables. Never echo them; secrets are masked, values derived from them are not.
- **Fork PRs** do not receive secrets and the job fails closed. Do not switch to `pull_request_target` to work around it unless you understand the code-execution risk.
- **Sensitive eval data:** no share links, short artifact retention, private repos. Results contain full model outputs.

## Keeping CI useful

- Mark known, accepted failures in test metadata and exclude them from the PR tier rather than lowering the threshold globally.
- When CI catches a real regression, add the triggering input to the golden set.
- Pin the eval tool version; upgrade it deliberately and re-run the baseline to check nothing moved.
- Re-run the full tier after any model, quant, engine or gateway change (`quality-gates.md`).
- A PR tier that is flaky gets ignored: measure its noise (baseline against itself) before making it blocking.

## Official links

- promptfoo CI/CD guide: https://www.promptfoo.dev/docs/integrations/ci-cd/
- promptfoo GitHub Action guide: https://www.promptfoo.dev/docs/integrations/github-action/
- GitHub Actions secrets: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
