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
      .items.addFromFeedback({ datasetId: "d1" })
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
      .runs.compare({ baseRunId: "a", candidateRunId: "b" })
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
      .exportPromptfoo({
        datasetId: "d1",
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

describe("createAiEvals reads and writes", () => {
  const fullRun = {
    ...runRow("failed"),
    organization_id: "o1",
    scorers: [
      { name: "tone", kind: "llm_judge", criteria: "polite", threshold: 0.4 },
      { name: "layout", kind: "json_schema", jsonSchema: { type: "object" } },
      { name: "weird", kind: "other" },
      "not a scorer",
    ],
    summary: {
      total: 3,
      passed: 2,
      failed: 1,
      errored: 0,
      passRate: 0.67,
      scorers: { tone: { avg: 0.8, passRate: 1 }, broken: "x" },
    },
    finished_at: AT,
  };

  const result = (extra: Record<string, unknown> = {}) => ({
    run_id: "r1",
    item_id: "i1",
    output: "A",
    scores: {
      tone: { score: 0.9, passed: true, reason: "kind" },
      layout: { passed: false },
      broken: "x",
    },
    passed: true,
    error: null,
    latency_ms: 12,
    created_at: AT,
    ...extra,
  });

  it("creates datasets and items", async () => {
    const { transport, calls } = fake({
      create_eval_dataset: () => ({
        id: "d1",
        organization_id: "o1",
        name: "support",
        description: "d",
        created_at: AT,
      }),
      add_eval_items: () => 2,
      list_eval_items: () => [
        {
          ...item("i1", "a", "A"),
          metadata: { tag: "x" },
          source_chat_id: "c1",
          source_message_id: "m1",
        },
      ],
    });

    const evals = createAiEvals({ transport });

    const dataset = await evals.datasets
      .create({ name: "support", organizationId: "o1", description: "d" })
      .orThrow();

    expect(dataset).toMatchObject({ id: "d1", organizationId: "o1" });

    await expect(
      evals.items
        .add({
          datasetId: "d1",
          items: [{ input: "a" }, { input: "b", expected: "B" }],
        })
        .orThrow(),
    ).resolves.toBe(2);

    const listed = await evals.items
      .list({ datasetId: "d1", pendingRun: "r1", after: "i0", limit: 5 })
      .orThrow();

    expect(listed[0]).toMatchObject({
      metadata: { tag: "x" },
      sourceChatId: "c1",
      sourceMessageId: "m1",
    });
    expect(calls.at(-1)?.args).toMatchObject({
      pending_run: "r1",
      after: "i0",
      max_rows: 5,
    });
  });

  it("creates, reads, lists, records and finishes runs", async () => {
    const { transport, calls } = fake({
      create_eval_run: () => fullRun,
      get_eval_run: (args) => (args["run"] === "none" ? null : fullRun),
      list_eval_runs: () => [fullRun, runRow("cancelled")],
      record_eval_result: () => result(),
      list_eval_results: () => [
        result(),
        result({ latency_ms: "slow", error: "x" }),
      ],
      finish_eval_run: () => fullRun,
    });

    const evals = createAiEvals({ transport });

    const created = await evals.runs
      .create({
        datasetId: "d1",
        promptName: "greet",
        promptVersion: 2,
        model: "m",
        scorers: [exactMatch()],
      })
      .orThrow();

    expect(created).toMatchObject({
      status: "failed",
      organizationId: "o1",
      summary: { total: 3, scorers: { tone: { avg: 0.8, passRate: 1 } } },
    });
    expect(created.scorers).toEqual([
      { name: "tone", kind: "llm_judge", criteria: "polite", threshold: 0.4 },
      { name: "layout", kind: "json_schema", jsonSchema: { type: "object" } },
    ]);
    expect(created.finishedAt).toBeDefined();

    await expect(evals.runs.get("none").orThrow()).resolves.toBeUndefined();
    await expect(evals.runs.get("r1").orThrow()).resolves.toMatchObject({
      id: "r1",
    });

    const listed = await evals.runs
      .list({ datasetId: "d1", limit: 2 })
      .orThrow();

    expect(listed.map((run) => run.status)).toEqual(["failed", "cancelled"]);

    const recorded = await evals.runs
      .record({
        runId: "r1",
        itemId: "i1",
        result: { output: "A", latencyMs: 12 },
      })
      .orThrow();

    expect(recorded.scores["tone"]).toEqual({
      score: 0.9,
      passed: true,
      reason: "kind",
    });
    expect(recorded.scores["layout"]).toEqual({ score: 0, passed: false });
    expect(recorded.latencyMs).toBe(12);

    const results = await evals.runs
      .results({ runId: "r1", onlyFailed: true, after: "i0", limit: 3 })
      .orThrow();

    expect(results[1]).toMatchObject({ latencyMs: undefined, error: "x" });
    expect(calls.at(-1)?.args).toMatchObject({
      only_failed: true,
      max_rows: 3,
    });

    await expect(
      evals.runs.finish({ runId: "r1" }).orThrow(),
    ).resolves.toMatchObject({ id: "r1" });
    expect(calls.at(-1)?.args).toMatchObject({ status: "completed" });
  });

  it("falls back to empty summaries and counts in a sparse comparison", async () => {
    const { transport } = fake({
      compare_eval_runs: () => ({
        base: null,
        candidate: null,
        regressions: [
          { item_id: "i1", base_output: "a", candidate_output: "b" },
        ],
        improvements: [{ item_id: "i2", base_score: 0, candidate_score: 1 }],
      }),
    });

    const compared = await createAiEvals({ transport })
      .runs.compare({ baseRunId: "a", candidateRunId: "b", scoreDrop: 0.2 })
      .orThrow();

    expect(compared).toMatchObject({
      passRateDelta: 0,
      unchanged: 0,
      missing: 0,
      base: { total: 0 },
    });
    expect(compared.regressions[0]).toEqual({
      itemId: "i1",
      baseScore: undefined,
      candidateScore: undefined,
      baseOutput: "a",
      candidateOutput: "b",
    });
    expect(compared.improvements[0]).toMatchObject({
      baseScore: 0,
      candidateScore: 1,
    });
  });
});
