---
name: structured-outputs
description: Force LLM output to match a JSON schema, regex, choice list or grammar with guided decoding on vLLM, SGLang, TensorRT-LLM, llama.cpp, Ollama, TensorFold and ExLlamaV3/TabbyAPI. Per-engine flags and request shapes (response_format json_schema, structured_outputs, --structured-outputs-config.backend, --grammar-backend, guided_decoding_backend, --grammar, --json-schema, Ollama format), backends (xgrammar, guidance, outlines, llguidance), and a validity and accuracy gate. Use for invalid JSON, guided_json removed, Failed to parse grammar, empty content with thinking, slow first request. Tool-call parsers are in tool-calling-parsers; thinking toggles in reasoning-models.
license: MIT
compatibility: Needs shell access to the serving host or an OpenAI-compatible endpoint, curl and jq. Restarting an engine, changing serve flags or enabling a backend needs the user's explicit approval. Works on Linux, macOS and Windows hosts that run the engines.
metadata:
  author: ScaleDockHQ
  version: "0.1.0"
---

# Structured Outputs

Make a self-hosted model return output that always parses (JSON schema, regex, choice, grammar), with the right flag and request shape for the engine in use, and prove with a gate that validity went up without hurting task accuracy.

**Scope:** this cross-product technique, with per-engine flags and quality gates. Product install and tuning stay in product skills (see Companion skills).

Work through the steps in order. Load a reference only when a step names it.

## Discover first

Inspect the live system before changing anything. Every command is read-only and never prints secrets. Replace the port with the one in use (`ss -ltnp` shows listeners).

```bash
# Which engine, which version
command -v vllm && vllm --version
python3 -m sglang.launch_server --help 2>/dev/null | head -3
command -v trtllm-serve llama-server ollama tensorfold-native
llama-server --version 2>&1 | head -2; ollama --version

# What the running server advertises (OpenAI-compatible)
curl -s http://127.0.0.1:8000/v1/models | jq '.data[] | {id, max_model_len}'
ollama list                                                 # Ollama: installed models

# Flags the running process was started with
ps -eo args | grep -E 'vllm|sglang|trtllm|llama-server|tensorfold|tabby' | grep -v grep | cut -c1-400
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Command}}' 2>/dev/null | cut -c1-300

# Is a grammar library present (TensorFold needs xgrammar)
python3 -c "import xgrammar; print(xgrammar.__version__)" 2>&1 | tail -1
```

Ask the user only what discovery cannot show: the schema or format required, which clients send it, whether thinking is on, and what validity rate and latency they need.

## Decision flow

1. **Which constraint?** JSON object with a schema -> JSON schema. Fixed label set -> `choice` (vLLM, TensorFold) or an enum in a schema. Fixed text pattern -> regex. A custom language (SQL subset, DSL) -> grammar (EBNF on vLLM, SGLang, TensorRT-LLM, TensorFold; GBNF on llama.cpp). Wrapped tool-call text -> structural tag, or use `tool-calling-parsers`.
2. **Which engine and shape?** Pick the row in `references/engine-flags.md`; use its exact flag and request field. Engines differ: the OpenAI `response_format` works on most, but regex and grammar use engine-specific fields (`structured_outputs`, `extra_body.regex`, `response_format.type: regex`, `grammar`).
3. **Thinking model?** The constraint must apply after the reasoning ends. Check the reasoning parser is set (`reasoning-models`), and read the vLLM `enable_in_reasoning` note in `references/engine-flags.md`.
4. **Engine cannot do it?** Ollama has `format` for JSON only; llama.cpp covers a schema subset; TensorFold needs xgrammar and a qualified engine. Otherwise fall back to a client-side validate-and-retry loop, and say so.
5. **Gate it.** Any new constraint, backend or engine version is a validity and accuracy change; run the gate in `references/quality-gate-and-pitfalls.md` before it serves users.

## Rules

- **Ask before changing the system.** Adding serve flags, installing xgrammar or restarting an engine needs approval and an undo path (keep the old command line).
- **Secrets never touch output.** Keys live in `0600` files or environment variables (`LLM_API_KEY_FILE`, `LLM_API_KEY`); never echo them or put them in command lines you print.
- **Verify upstream.** Flags, backend lists and defaults come from the installed `--help` and upstream docs; `references/engine-flags.md` records versions and date.
- **Constraints change outputs.** Gate with the `llm-evals` skill (install: `npx skills add ScaleDockHQ/llm-skills --skill llm-evals`): schema-validity rate plus task accuracy for baseline versus candidate, finish reasons, latency including cold start, and a written rollback.
- **Describe the schema in the prompt too.** The grammar masks tokens; it does not tell the model what you want. llama.cpp does not inject the schema.
- **Keep schemas strict and small.** All properties required, `additionalProperties: false`, optional fields as nullable types, no keywords the engine skips.

## Techniques per engine

- [ ] Pick the constraint type and the engine row -> `references/engine-flags.md`.
- [ ] vLLM: `--structured-outputs-config.backend` (`auto` default; pin `xgrammar` or `guidance` after gating); send `structured_outputs` or `response_format`. The old `guided_*` fields were removed in v0.12.0.
- [ ] SGLang: `--grammar-backend xgrammar|outlines|llguidance|none`; Outlines has no EBNF; `regex` and `ebnf` ride in `extra_body`.
- [ ] TensorRT-LLM: `guided_decoding_backend: xgrammar|llguidance` in the YAML passed with `--config`; `response_format` types `json`, `regex`, `ebnf`, `structural_tag`.
- [ ] llama.cpp: `--json-schema`, `--grammar` or per-request `json_schema`, `grammar`, `response_format`; check the schema-subset limits.
- [ ] Ollama: `format` set to `"json"` or a schema object; or OpenAI `response_format`; local models only.
- [ ] TensorFold: needs `tensorfold[grammar]` or `libtfgrammar`; only some native engines enforce it.
- [ ] ExLlamaV3: `LLGuidanceFilter` in the library; TabbyAPI `json_schema`, `regex_pattern`, `grammar_string` or `response_format`.
- [ ] Warm each schema once after startup so the first user request does not pay the compile.
- [ ] Verify: run `scripts/probe.sh BASE_URL MODEL [shape]` (shapes: `response_format`, `vllm`, `sglang-regex`, `ollama-native`). It prints the HTTP status, finish reason and whether the content parses with the required keys. Then run the gate; the change is done when validity meets the threshold you wrote, accuracy is not worse than baseline beyond noise, and no new `length` truncations appear.

## Reference index

- `references/engine-flags.md`: capability matrix, exact flags, request shapes, defaults and limits per engine (vLLM, SGLang, TensorRT-LLM, llama.cpp, Ollama, TensorFold, ExLlamaV3/TabbyAPI). Load at the first technique step.
- `references/quality-gate-and-pitfalls.md`: the validity and accuracy gate procedure, rollback and the pitfall list. Load before enabling anything for users.
- `scripts/probe.sh`: read-only request that checks a constraint end to end (bash 3.2+, curl, jq).

## Companion skills

- `llm-evals`: build the golden set and run the gate. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-evals`.
- `tool-calling-parsers`: tool-call parsers and strict tool schemas. Install: `npx skills add ScaleDockHQ/llm-skills --skill tool-calling-parsers`.
- `reasoning-models`: reasoning parsers, thinking toggles and budgets. Install: `npx skills add ScaleDockHQ/llm-skills --skill reasoning-models`.
- `vllm`: vLLM install and tuning. Install: `npx skills add ScaleDockHQ/llm-skills --skill vllm`.
- `sglang`: SGLang install and tuning. Install: `npx skills add ScaleDockHQ/llm-skills --skill sglang`.
- `tensorrt-llm`: TensorRT-LLM engines and `trtllm-serve`. Install: `npx skills add ScaleDockHQ/llm-skills --skill tensorrt-llm`.
- `llama-cpp`: llama.cpp server and GGUF. Install: `npx skills add ScaleDockHQ/llm-skills --skill llama-cpp`.
- `ollama`: Ollama install and API. Install: `npx skills add ScaleDockHQ/llm-skills --skill ollama`.
- `tensorfold`: TensorFold serving. Install: `npx skills add ScaleDockHQ/llm-skills --skill tensorfold`.
- `exllamav3`: ExLlamaV3 and TabbyAPI. Install: `npx skills add ScaleDockHQ/llm-skills --skill exllamav3`.
- `choosing-inference-engine`: pick an engine when constrained decoding is a requirement. Install: `npx skills add ScaleDockHQ/llm-skills --skill choosing-inference-engine`.
- `llm-gateway`: gateway-side fields and fallbacks for structured requests. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-gateway`.
- `self-hosted-llms`: the full self-hosted stack these flags plug into. Install: `npx skills add ScaleDockHQ/llm-skills --skill self-hosted-llms`.
