# LiteLLM and clients

> Verified against Vercel AI Gateway docs (coding-agents/claude-code, openai-compat) and LiteLLM Vercel AI Gateway provider docs, 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/coding-agents/claude-code>, `/sdks-and-apis/openai-chat-completions`, <https://docs.litellm.ai/docs/providers/vercel_ai_gateway>.

## Claude Code

One command detects and configures supported agents:

```bash
npx vercel@latest ai-gateway setup                 # pick agents interactively
npx vercel ai-gateway setup --agent claude-code
```

It provisions or reuses a key, previews changes, writes `~/.claude/settings.json` with `ANTHROPIC_BASE_URL=https://ai-gateway.vercel.sh/claude-code`, empties `ANTHROPIC_API_KEY`, enables gateway model discovery in `/model`, and on macOS keeps the key in the Keychain. Review the preview before accepting.

Manual setup:

```bash
export ANTHROPIC_BASE_URL="https://ai-gateway.vercel.sh/claude-code"
export ANTHROPIC_AUTH_TOKEN="$(cat ~/.config/ai-gateway-key)"
export ANTHROPIC_API_KEY=""     # must be empty so Claude Code uses the token above
```

The CLI setup supports API-key auth only. A Claude subscription flow needs `ANTHROPIC_CUSTOM_HEADERS="x-ai-gateway-api-key: Bearer <key>"` configured by hand; see the page.

## OpenAI SDK

```python
import os
from openai import OpenAI
c = OpenAI(api_key=os.environ["AI_GATEWAY_API_KEY"], base_url="https://ai-gateway.vercel.sh/v1")
```

Extension fields such as `providerOptions` go in `extra_body`.

## LiteLLM

LiteLLM routes `vercel_ai_gateway/` to base URL `https://ai-gateway.vercel.sh/v1` and reads `VERCEL_AI_GATEWAY_API_KEY` or `VERCEL_OIDC_TOKEN`:

```yaml
model_list:
  - model_name: vercel-model
    litellm_params:
      model: vercel_ai_gateway/<creator>/<model>
      api_key: os.environ/VERCEL_AI_GATEWAY_API_KEY
```

Use the `litellm` skill for the proxy side: `npx skills add ScaleDockHQ/llm-skills --skill litellm`.

## Other agents

The gateway documents setups for Codex, Cursor, OpenCode, Gemini CLI, Copilot and more under `/coding-agents`. The CLI covers several in one run.
