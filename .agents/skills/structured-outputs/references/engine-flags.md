# Structured outputs: per-engine flags and request shapes

> Verified against vLLM v0.31.0 (docs: features/structured_outputs, features/tool_calling; vllm/config/structured_outputs.py), SGLang v0.5.21 (docs: advanced_features/structured_outputs, tool_parser; srt/arg_groups/choices.py), TensorRT-LLM v1.2.1 and docs main (features/guided-decoding; serve/openai_protocol.py), llama.cpp v0.6.0 (tools/server/README.md, grammars/README.md), Ollama v0.40.3 (docs: capabilities/structured-outputs), TensorFold v1.0.7 (docs/api.md), ExLlamaV3 v1.6.1 (examples, generator/filter), TabbyAPI main (README, endpoints/OAI/types/common.py, backends/exllamav3/grammar.py), 2026-10-11

Verify against the installed binary: flags and choice lists move between releases (`vllm serve --help=all`, `python -m sglang.launch_server --help`, `trtllm-serve --help`, `llama-server --help`).

## Capability matrix

| Engine        | JSON schema  | Regex | Choice | EBNF / grammar       | Structural tag | Backends (grammar engines)                                                 |
| ------------- | ------------ | ----- | ------ | -------------------- | -------------- | -------------------------------------------------------------------------- |
| vLLM          | yes          | yes   | yes    | yes                  | yes            | `auto` (default), `xgrammar`, `guidance`, `outlines`, `lm-format-enforcer` |
| SGLang        | yes          | yes   | no     | yes (not `outlines`) | yes            | `xgrammar` (default), `outlines`, `llguidance`, `none`                     |
| TensorRT-LLM  | yes          | yes   | no     | yes                  | xgrammar only  | `xgrammar`, `llguidance` (`llguidance` PyTorch backend only)               |
| llama.cpp     | yes (subset) | no    | no     | GBNF                 | no             | built in                                                                   |
| Ollama        | yes          | no    | no     | no                   | no             | built in                                                                   |
| TensorFold    | yes          | yes   | yes    | yes (EBNF)           | not documented | xgrammar (needs `tensorfold[grammar]` or `libtfgrammar`)                   |
| ExLlamaV3 lib | yes          | yes   | no     | yes                  | no             | `LLGuidanceFilter` (recommended), `FormatronFilter`                        |

TabbyAPI (the ExLlamaV3 server) advertises "JSON schema + Regex + EBNF" in its README.

## vLLM (v0.31.0)

- Backend flag: `--structured-outputs-config.backend {auto,xgrammar,guidance,outlines,lm-format-enforcer}`; default `auto`, which picks per request and "is subject to change in each release". Pin a backend when you need reproducible behavior.
- Other config fields: `.disable_any_whitespace` (default false; only valid with `xgrammar` or `guidance`; startup error otherwise), `.disable_additional_properties` (default false; `guidance` only), `.enable_in_reasoning` (default false), `.reasoning_parser`, `.reasoning_parser_plugin`.
- Request shapes (OpenAI chat or completions; non-standard keys go in `extra_body`):

```json
{"structured_outputs": {"choice": ["positive", "negative"]}}
{"structured_outputs": {"regex": "\\w+@\\w+\\.com\\n"}, "stop": ["\n"]}
{"structured_outputs": {"json": {"type": "object", "properties": {}}}}
{"structured_outputs": {"grammar": "root ::= \"yes\" | \"no\""}}
{"structured_outputs": {"structural_tag": "..."}}
{"response_format": {"type": "json_schema", "json_schema": {"name": "car", "schema": {}}}}
```

- Removed in v0.12.0: `guided_json`, `guided_regex`, `guided_choice`, `guided_grammar`, `guided_whitespace_pattern`, top-level `structural_tag`, and `guided_decoding_backend`. Old clients that still send them need an update.
- Regex dialect depends on the backend: `xgrammar`, `guidance` and `outlines` use Rust-style regex; `lm-format-enforcer` uses Python `re`.
- Reasoning models: structured output applies after the reasoning ends when `--reasoning-parser` is set (for example `deepseek_r1`). With Qwen3 Coder and reasoning on, structured output can become disabled unless the reasoning is parsed into `reasoning`; add `--structured-outputs-config.enable_in_reasoning=True` (v0.11.2+ note) to force both.
- Tool calls: `tool_choice` set to a named function or `required` uses the structured-output backend, so the first request after startup pays a grammar compile ("several seconds or more"), then it is cached. `tool_choice: auto` is constrained only with `strict: true` tools or `--tool-strict-level function|parameter` (see the `tool-calling-parsers` skill). `VLLM_ENFORCE_STRICT_TOOL_CALLING=false` disables structural tags.
- Docs tip: also describe the schema in the prompt; it "can improve the results notably".

## SGLang (v0.5.21)

- Backend flag: `--grammar-backend {xgrammar,outlines,llguidance,none}`; default `xgrammar`. If the tokenizer is not supported by xgrammar the source logs "Falling back to grammar_backend='none'"; check the startup log, and what a structured request does in that state is not verified.
- Support: XGrammar handles JSON schema, regex and EBNF; Outlines handles JSON schema and regex only; Llguidance handles JSON schema, regex and EBNF. Only one of `json_schema`, `regex`, `ebnf` per request.
- Request shapes (OpenAI endpoint):

```json
{"response_format": {"type": "json_schema", "json_schema": {"name": "foo", "schema": {}}}}
{"regex": "(Paris|London)"}
{"ebnf": "root ::= city\ncity ::= \"London\" | \"Paris\""}
{"response_format": {"type": "structural_tag", "structures": [{"begin": "<function=f>", "schema": {}, "end": "</function>"}], "triggers": ["<function="]}}
```

Put `regex` and `ebnf` in `extra_body` with the OpenAI SDK. On the native `/generate` API they go inside `sampling_params` (`regex`, `ebnf`, `json_schema`). The structural-tag shape above is the legacy form; the doc also shows a newer `{"type": "structural_tag", "format": {"type": "triggered_tags", ...}}` form that follows xgrammar's structural-tag format.

- Tool choice `required` or a named function is implemented with EBNF; "fully supported" with xgrammar, possibly not with `outlines`.
- Strict tool calling: env var `SGLANG_TOOL_STRICT_LEVEL` (`0` off, default; `1` function; `2` parameter).
- Docs tip: say the format in the prompt as well.

## TensorRT-LLM (v1.2.1 release; docs main)

- Enable in the YAML passed with `--config` (alias `--extra_llm_api_options`):

```yaml
guided_decoding_backend: xgrammar # or llguidance (PyTorch backend only)
```

```bash
trtllm-serve <model> --config config.yaml
```

Expect the startup log line `Guided decoder initialized with backend: GuidedDecodingBackend.XGRAMMAR`.

- `response_format` shapes (OpenAI chat): `{"type": "json", "schema": {...}}`, `{"type": "regex", "regex": "(Paris|London)"}`, `{"type": "ebnf", "ebnf": "..."}`, `{"type": "structural_tag", "format": {...}}`. The v1.2.1 server code also accepts `json_schema` and `json_object`, and `text`.
- Structural tag works with the `xgrammar` backend only. XGrammar: JSON schema, regex, EBNF, structural tag. LLGuidance: JSON schema, regex, EBNF.
- Offline LLM API: `LLM(model, guided_decoding_backend="xgrammar")` plus `SamplingParams(guided_decoding=GuidedDecodingParams(json=... | regex=... | grammar=... | structural_tag=...))`.

## llama.cpp (v0.6.0)

| Where                      | Flag or field                                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `llama-server`/`llama-cli` | `--grammar GRAMMAR`, `--grammar-file FNAME`, `-j, --json-schema SCHEMA`, `-jf, --json-schema-file FILE`                                                 |
| `/completion` body         | `grammar`, `json_schema`                                                                                                                                |
| `/v1/chat/completions`     | `response_format`: `{"type": "json_object"}`, `{"type": "json_object", "schema": {...}}` or `{"type": "json_schema", "json_schema": {"schema": {...}}}` |

- `--grammar` and `--json-schema` are server-start defaults; how they combine with a per-request `grammar` or `response_format` is not documented (unverified), so avoid setting both.
- The schema constrains output only; it is not injected into the prompt, so describe it in the prompt too (does not apply to tool calling, where schemas are injected).
- Schema to GBNF is a subset. Documented limits: `additionalProperties` defaults to `false`; unsupported keywords are skipped silently; no mixing `properties` with `anyOf`/`oneOf` in one type; `prefixItems` broken; `minimum`/`maximum` only for `integer`; nested `$ref` broken; `pattern` must start with `^` and end with `$`; no `patternProperties`, `uniqueItems`, `contains`, `not`, `if/then/else`; remote `$ref` unsupported in C++; `string` formats lack `uri` and `email`.
- GBNF tip from upstream: write bounded repetition as `x{0,N}`, not `x? x? x?`, which "may result in extremely slow sampling".
- GBNF can match special tokens by id (`<[1000]>`) or by a string that tokenizes to exactly one token.
- An invalid grammar sent to `/completions` returns an error with message `Failed to parse grammar`.

## Ollama (v0.40.3)

- Native API: `format` is `"json"` or a JSON-schema object (`/api/chat`, `/api/generate`). OpenAI-compatible API: `response_format` is a supported request field.
- Ollama Cloud does not support structured outputs (upstream note).
- Upstream tips: pass the schema in the prompt too; set `temperature` to `0` for more deterministic completions.
- No documented regex, grammar or structural-tag option.

## TensorFold (v1.0.7)

- Accepted fields (both backends): `response_format` (`json_schema` or `json_object`), plus vLLM-style `guided_json`, `guided_regex`, `guided_choice`, `guided_grammar` (EBNF) and `structured_outputs` (`json`, `json_object`, `regex`, `choice`, `grammar`).
- Needs xgrammar: `pip install 'tensorfold[grammar]'`. The native Zig server uses `libtfgrammar` (a C ABI over xgrammar v0.2.8) shipped in `lib/` beside `bin/` in release archives. Without it, structured requests get HTTP 400 and everything else serves.
- Native engines: Nemotron (Metal and CUDA) and Qwen3.5-2B (Metal) enforce it; other native engines answer a structured request with HTTP 400.
- Speculative drafting stays on and the constrained reply equals the `"draft": false` reply. With thinking on, the grammar starts after the think end. JSON grammars allow at most 32 blank characters between tokens. A reply cut at `max_tokens` is incomplete (`finish_reason: "length"`).
- HTTP 400 comes before any token for: a malformed field, a grammar xgrammar cannot compile, a server without xgrammar, a grammar sent together with `tool_choice: "required"` or a named function, and `logprobs` with a grammar or tools.

## ExLlamaV3 and TabbyAPI

- Library (v1.6.1): `exllamav3/generator/filter/` ships `llguidance.py` and `formatron.py`. The Formatron example says that dependency "is no longer maintained" and recommends the LLGuidance filter (`examples/constrained_generation_llg.py`).
- TabbyAPI request fields found in `endpoints/OAI/types/common.py`: `json_schema`, `regex_pattern`, `grammar_string`, and `response_format`. Its grammar code uses llguidance and accepts Lark syntax or llama.cpp GBNF.
- TabbyAPI has no tagged GitHub release; record the commit you deploy.

## Official links

- vLLM: https://docs.vllm.ai/en/latest/features/structured_outputs/
- SGLang: https://docs.sglang.ai/advanced_features/structured_outputs.html
- TensorRT-LLM: https://nvidia.github.io/TensorRT-LLM/latest/features/guided-decoding.html
- llama.cpp: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md and https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md
- Ollama: https://docs.ollama.com/capabilities/structured-outputs
- TensorFold: https://github.com/ashhart/TensorFold/blob/main/docs/api.md
- ExLlamaV3: https://github.com/turboderp-org/exllamav3
- TabbyAPI: https://github.com/theroyallab/tabbyAPI
- xgrammar: https://github.com/mlc-ai/xgrammar
