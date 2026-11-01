# LLM-as-judge

> Verified against promptfoo 0.124.1 docs (model-graded assertions, llm-rubric, vLLM judge guide), 2026-10-11

Using a model to grade another model's output. Powerful for open-ended tasks, and the easiest place to fool yourself.

## When to use a judge

Use one only when a deterministic check cannot express "good":

| Need                                              | Prefer                                                        |
| ------------------------------------------------- | ------------------------------------------------------------- |
| Contains a fact, ID, number                       | `contains`, `icontains`, `contains-all`, `regex`              |
| Valid JSON / schema                               | `is-json` with schema, `contains-json`                        |
| Tool call shape                                   | `is-valid-openai-tools-call`                                  |
| Close to a reference text                         | `similar` (embeddings), `levenshtein`, `rouge-n`              |
| Tone, helpfulness, completeness, policy adherence | `llm-rubric`                                                  |
| Factual agreement with a reference                | `factuality`                                                  |
| Pick the best of several outputs                  | `select-best`                                                 |
| RAG grounding                                     | `context-faithfulness`, `context-recall`, `context-relevance` |

## Configure the judge once

The grader is a separate provider. Set it in `defaultTest.options.provider` so every model-graded assertion uses it:

```yaml
defaultTest:
  options:
    provider:
      id: openai:chat:<judge-model-id>
      label: judge
      config:
        apiBaseUrl: "{{ env.JUDGE_BASE_URL }}"
        apiKeyEnvar: JUDGE_API_KEY
        temperature: 0
        max_tokens: 2048
        showThinking: false # judges must not grade their own scratchpad
```

Do not also put `provider: openai:chat:<id>` on individual assertions: an assertion-level provider overrides the default object and drops its `apiBaseUrl`, key and `showThinking` settings. If only one assertion needs a different judge, give it the full provider object.

For reasoning judges served by vLLM, either set `showThinking: false` or disable thinking for judge calls with `passthrough: { chat_template_kwargs: { enable_thinking: false } }` (Qwen3/GLM-style templates). If `max_tokens` is too low the model may stop inside `<think>`, and raw thinking text lands in `content`.

## Write rubrics as criteria, with a threshold

```yaml
assert:
  - type: llm-rubric
    value: |
      PASS only if all are true:
      1. States the refund window from the policy excerpt.
      2. Does not promise anything the excerpt does not say.
      3. Ends with a next step for the customer.
    threshold: 0.8
```

Without `threshold`, PASS comes from the judge's boolean `pass`, and `score` does not affect the result (a `{pass: true, score: 0}` verdict passes). With `threshold`, both `pass` and `score >= threshold` must hold.

Custom grading prompts: `rubricPrompt` on the assertion. Keep it in version control and treat a change to it like a change to the eval set.

## Judge the judge (calibration)

Before a judge influences a decision:

1. Take 20–50 items, have a human label each output pass/fail against the same rubric.
2. Run the judge on the same outputs.
3. Compute agreement: matching verdicts / items. Inspect every disagreement.
4. Fix the rubric (usually ambiguity) and repeat until agreement is acceptable for the decision at hand.
5. Record judge model ID, endpoint, prompt version and agreement in the decision record.

Re-calibrate when you change the judge model, its quantization, its prompt, or the task.

## Bias and failure modes

- **Self-preference:** models rate outputs from their own family higher. Use a judge from a different family than the candidate, and never let the candidate judge itself on a ship decision.
- **Position bias** in pairwise comparisons (`select-best`): the first or second option wins more often. Swap order and require consistent wins.
- **Length bias:** longer answers look better. Add "Do not reward length" and a length-related deterministic check.
- **Leniency drift:** a rubric with vague words ("good", "helpful") passes nearly everything. Make criteria observable.
- **Format failures:** the judge must return the verdict JSON promptfoo expects; small or heavily quantized judges break this more often. Watch for grader ERROR rows.
- **Cost and latency:** a judge call per test per provider. Cache the candidate outputs, not the judge, when iterating on rubrics.

## Self-hosted judges

A local judge (vLLM, SGLang, llama.cpp, or via LiteLLM) keeps sensitive outputs in-house. Use the largest model you can afford; tiny models are for wiring tests only. Pin the exact checkpoint and quantization, since a quantized judge is a different judge.

## Official links

- Model-graded assertions: https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/
- llm-rubric (threshold semantics, rubricPrompt): https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/llm-rubric/
- vLLM as a judge (showThinking, enable_thinking): https://www.promptfoo.dev/docs/providers/vllm/
