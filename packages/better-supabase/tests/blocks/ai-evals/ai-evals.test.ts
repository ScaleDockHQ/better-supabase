import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createAiEvals,
  createEvalJob,
  exactMatch,
  jsonSchema,
  llmJudge,
  toPromptfooConfig,
} from "../../../src/blocks/ai-evals/index.ts";

const AT = "2026-01-01T00:00:00Z";

function fake(
  handlers: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];

      return handler
        ? Promise.resolve(handler(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };

  return { transport, calls };
}

const item = (id: string, input: unknown, expected?: unknown) => ({
  id,
  dataset_id: "d1",
  input,
  expected: expected ?? null,
  metadata: {},
  source_chat_id: null,
  source_message_id: null,
  created_at: AT,
});

const runRow = (status = "running") => ({
  id: "r1",
  dataset_id: "d1",
  organization_id: null,
  prompt_name: "greet",
  prompt_version: 2,
  model: "m",
  scorers: [{ name: "exact_match", kind: "exact_match" }],
  status,
  summary: null,
  created_at: AT,
  finished_at: null,
});

describe("scorers", () => {
  it("matches text and JSON values", async () => {
    const scorer = exactMatch();

    await expect(
      scorer.score({ input: 1, output: " yes ", expected: "yes" }),
    ).resolves.toMatchObject({ passed: true, score: 1 });

    await expect(
      scorer.score({
        input: 1,
        output: '{"b":1,"a":2}',
        expected: { a: 2, b: 1 },
      }),
    ).resolves.toMatchObject({ passed: true });

    await expect(
      scorer.score({ input: 1, output: "no", expected: { output: "yes" } }),
    ).resolves.toMatchObject({ passed: false });

    await expect(
      scorer.score({ input: 1, output: "x", expected: undefined }),
    ).resolves.toMatchObject({ passed: false });
  });

  it("validates JSON through a Standard Schema", async () => {
    const schema = {
      "~standard": {
        version: 1 as const,
        vendor: "test",
        validate: (value: unknown) =>
          typeof value === "object" && value !== null && "ok" in value
            ? { value }
            : { issues: [{ message: "ok is required" }] },
      },
    };

    const scorer = jsonSchema(schema);

    await expect(
      scorer.score({ input: 1, output: '{"ok":true}', expected: undefined }),
    ).resolves.toMatchObject({ passed: true });

    await expect(
      scorer.score({ input: 1, output: "{}", expected: undefined }),
    ).resolves.toMatchObject({ passed: false, reason: "ok is required" });

    await expect(
      scorer.score({ input: 1, output: "nope", expected: undefined }),
    ).resolves.toMatchObject({ passed: false });
  });

  it("applies the judge threshold and survives a judge error", async () => {
    const scorer = llmJudge(
      { judge: () => Promise.resolve({ score: 0.6 }) },
      { criteria: "polite", threshold: 0.5 },
    );

    await expect(
      scorer.score({ input: 1, output: "x", expected: undefined }),
    ).resolves.toMatchObject({ passed: true, score: 0.6 });

    const broken = llmJudge(
      { judge: () => Promise.reject(new Error("boom")) },
      { criteria: "polite" },
    );

    await expect(
      broken.score({ input: 1, output: "x", expected: undefined }),
    ).resolves.toMatchObject({ passed: false });
  });

  it("refuses a judge built for another API version", () => {
    expect(() =>
      llmJudge(
        { apiVersion: 2, judge: () => Promise.resolve({ score: 1 }) } as never,
        { criteria: "x" },
      ),
    ).toThrow(/API 2/);
  });
});

describe("createAiEvals", () => {
  it("copies rated replies into a dataset", async () => {
    const { transport, calls } = fake({
      add_eval_items_from_feedback: () => 3,
    });

    const added = await createAiEvals({ transport })
      .items.addFromFeedback("d1")
      .orThrow();

    expect(added).toBe(3);
    expect(calls[0]?.args).toMatchObject({ dataset: "d1", rating: -1 });
  });

  it("reads a comparison", async () => {
    const summary = {
      total: 2,
      passed: 1,
      failed: 1,
      errored: 0,
      passRate: 0.5,
      scorers: {},
    };

    const { transport } = fake({
      compare_eval_runs: () => ({
        base: summary,
        candidate: { ...summary, passed: 0, passRate: 0 },
        pass_rate_delta: -0.5,
        regressions: [{ item_id: "i1", base_score: 1, candidate_score: 0 }],
        improvements: [],
        unchanged: 1,
        missing: 0,
      }),
    });

    const compared = await createAiEvals({ transport })
      .runs.compare("a", "b")
      .orThrow();

    expect(compared.passRateDelta).toBe(-0.5);
    expect(compared.regressions[0]).toMatchObject({
      itemId: "i1",
      baseScore: 1,
    });
  });

  it("exports every item as a promptfoo test", async () => {
    const { transport } = fake({
      list_eval_items: () => [
        item("i1", { question: "2+2" }, "4"),
        item("i2", "hello"),
      ],
    });

    const config = await createAiEvals({ transport })
      .exportPromptfoo("d1", {
        prompt: "Answer: {{question}}",
        model: "openai:gpt-4.1-mini",
        scorers: [
          exactMatch(),
          llmJudge(
            { judge: () => Promise.resolve({ score: 1 }) },
            { criteria: "kind" },
          ),
        ],
      })
      .orThrow();

    expect(config.providers).toEqual(["openai:gpt-4.1-mini"]);
    expect(config.tests[0]).toMatchObject({
      vars: { question: "2+2" },
      assert: [
        { type: "equals", value: "4" },
        { type: "llm-rubric", value: "kind", threshold: 0.7 },
      ],
    });
    expect(config.tests[1]?.vars).toEqual({ input: "hello" });
    expect(config.tests[1]?.assert).toHaveLength(1);
  });
});

describe("toPromptfooConfig", () => {
  it("keeps the schema of a json_schema scorer", () => {
    const config = toPromptfooConfig([{ id: "i1", input: "x" }], {
      description: "d",
      prompt: "p",
      model: "m",
      scorers: [
        { name: "shape", kind: "json_schema", jsonSchema: { type: "object" } },
      ],
    });

    expect(config.tests[0]?.assert).toEqual([
      { type: "is-json", value: { type: "object" }, metric: "shape" },
    ]);
  });
});

describe("createEvalJob", () => {
  it("scores the pending items, records errors and closes the run", async () => {
    const recorded: Record<string, unknown>[] = [];
    let pages = 0;

    const { transport } = fake({
      get_eval_run: () => runRow(),
      list_eval_items: () => {
        pages += 1;

        return pages === 1 ? [item("i1", "a", "A"), item("i2", "b", "B")] : [];
      },
      record_eval_result: (args) => {
        recorded.push(args);

        return {
          run_id: "r1",
          item_id: args["item"],
          output: args["output"] ?? null,
          scores: args["scores"],
          passed: false,
          error: args["error"] ?? null,
          latency_ms: 1,
          created_at: AT,
        };
      },
      finish_eval_run: () => runRow("completed"),
    });

    const evals = createAiEvals({ transport });

    const handler = createEvalJob({
      evals,
      scorers: [exactMatch()],
      task: (entry) =>
        entry.id === "i2"
          ? Promise.reject(new Error("model down"))
          : Promise.resolve("A"),
    });

    const result = await handler({ runId: "r1" });

    expect(result).toMatchObject({ processed: 2, done: true });
    expect(recorded[0]?.["scores"]).toMatchObject({
      exact_match: { passed: true },
    });
    expect(recorded[1]).toMatchObject({ error: "model down", scores: {} });
  });

  it("skips a run that is already closed", async () => {
    const { transport } = fake({ get_eval_run: () => runRow("completed") });

    const handler = createEvalJob({
      evals: createAiEvals({ transport }),
      scorers: [],
      task: () => Promise.resolve(""),
    });

    await expect(handler({ runId: "r1" })).resolves.toMatchObject({
      processed: 0,
      done: true,
    });
  });
});
