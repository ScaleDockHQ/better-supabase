# Structured Outputs

An agent skill for forcing self-hosted LLM output to match a JSON schema, regex, choice list or grammar. It gives the exact flag and request shape per engine (vLLM, SGLang, TensorRT-LLM, llama.cpp, Ollama, TensorFold, ExLlamaV3/TabbyAPI), names the grammar backends (xgrammar, guidance, outlines, llguidance), lists engine limits and the removed `guided_*` fields, and gates the change on schema-validity rate and task accuracy before it serves users.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill structured-outputs
```

## Rules

- **Discover first.** Check the engine, version and running flags before proposing a change; every discovery command is read-only.
- **Ask before changing the system.** Serve flags, installs and restarts need approval and an undo path.
- **Constraints change outputs.** Gate with `llm-evals`: validity rate, task accuracy, finish reasons, cold-start latency, rollback.
- **Describe the schema in the prompt too.** The grammar masks tokens; it does not inform the model.
- **Never print secrets.** Keys come from `0600` files or environment variables.

## References

- [`references/engine-flags.md`](references/engine-flags.md): capability matrix, flags, request shapes, defaults and limits per engine.
- [`references/quality-gate-and-pitfalls.md`](references/quality-gate-and-pitfalls.md): validity and accuracy gate, rollback, pitfalls.
- [`scripts/probe.sh`](scripts/probe.sh): end-to-end constraint check against an OpenAI-compatible endpoint (bash, curl, jq).

## Companion skills

- `llm-evals`: golden sets and the quality gate.
- `tool-calling-parsers`: tool-call parsers and strict tool schemas.
- `reasoning-models`: reasoning parsers and thinking controls.
- `vllm`, `sglang`, `tensorrt-llm`, `llama-cpp`, `ollama`, `tensorfold`, `exllamav3`: engine install and tuning.
- `choosing-inference-engine`, `llm-gateway`, `self-hosted-llms`: engine choice, gateway and the full stack.

## License

MIT
