import { describe, expect, it } from "vitest";

import type {
  NoteTaker,
  Transcriber,
} from "../../src/blocks/activities/recordings.ts";
import type {
  AiTask,
  AiTaskRun,
  AiTaskRunner,
} from "../../src/blocks/ai-schedules/ai-schedules.ts";
import type {
  FundingClaim,
  FundingClaimChannel,
  FundingClaimFormat,
  FundingClaimLine,
} from "../../src/blocks/funding/funding.ts";
import type { Embedder } from "../../src/blocks/knowledge/knowledge.ts";
import type { MedicationCatalog } from "../../src/blocks/medications/medications.ts";
import type { WorkflowGraph } from "../../src/blocks/workflow-editor/graph.ts";
import type {
  BuilderStartCall,
  BuilderStarter,
  GraphCompiler,
} from "../../src/blocks/workflow-editor/workflow-editor.ts";

import { money } from "../../src/commerce/money.ts";
import { injectableOf } from "../../src/core/block-helpers.ts";
import {
  ConformanceError,
  testAiTaskRunner,
  testBuilderStarter,
  testEmbedder,
  testFundingClaimChannel,
  testFundingClaimFormat,
  testGraphCompiler,
  testMedicationCatalog,
  testNoteTaker,
  testTranscriber,
} from "../../src/testing/index.ts";

const failed = (report: { checks: readonly { name: string; ok: boolean }[] }) =>
  report.checks.filter((check) => !check.ok).map((check) => check.name);

describe("injectableOf", () => {
  it("accepts version 1 or none and refuses others", () => {
    const embedder: Embedder = { model: "m", embed: async () => [] };
    expect(injectableOf("embedder", embedder)).toBe(embedder);
    expect(injectableOf("embedder", undefined)).toBeUndefined();
    expect(() =>
      injectableOf("embedder", {
        ...embedder,
        apiVersion: 2,
      } as unknown as Embedder),
    ).toThrow(/embedder targets API 2/);
  });
});

describe("testEmbedder", () => {
  const embedder: Embedder = {
    apiVersion: 1,
    model: "fake",
    embed: async (values) => values.map((value) => [value.length, 1]),
  };

  it("passes a conforming embedder", async () => {
    expect(failed(await testEmbedder(embedder))).toEqual([]);
  });

  it("fails ragged or missing vectors", async () => {
    const ragged: Embedder = {
      model: "",
      embed: async (values) => values.slice(1).map(() => [Number.NaN]),
    };

    await expect(testEmbedder(ragged)).rejects.toBeInstanceOf(ConformanceError);
  });
});

describe("testAiTaskRunner", () => {
  const task = { id: "t" } as AiTask;
  const run = { id: "r" } as AiTaskRun;

  it("passes a runner that honors its signal", async () => {
    const runner: AiTaskRunner = Object.assign(
      async (_task: AiTask, _run: AiTaskRun, signal: AbortSignal) => {
        signal.throwIfAborted();

        return { chatId: "c" };
      },
      { apiVersion: 1 as const },
    );

    expect(failed(await testAiTaskRunner(runner, { task, run }))).toEqual([]);
  });

  it("fails a runner that ignores its signal", async () => {
    const runner: AiTaskRunner = async () => undefined;
    await expect(testAiTaskRunner(runner, { task, run })).rejects.toThrow(
      /has apiVersion 1[\s\S]*stops on an aborted signal/,
    );
  });
});

describe("testGraphCompiler", () => {
  const graph: WorkflowGraph = { nodes: [], edges: [] };

  it("passes a pure compiler", async () => {
    const compile: GraphCompiler = Object.assign(
      (input: WorkflowGraph) => ({ steps: input.nodes.length }),
      { apiVersion: 1 as const },
    );

    expect(failed(await testGraphCompiler(compile, { graph }))).toEqual([]);
  });

  it("fails a compiler that returns a new value each time", async () => {
    let n = 0;

    const compile: GraphCompiler = Object.assign(() => ({ at: (n += 1) }), {
      apiVersion: 1 as const,
    });

    await expect(testGraphCompiler(compile, { graph })).rejects.toThrow(
      /two compiles of one graph differ/,
    );
  });
});

describe("testBuilderStarter", () => {
  const call = { idempotencyKey: "k" } as BuilderStartCall;

  it("passes an idempotent starter", async () => {
    const start: BuilderStarter = Object.assign(
      async (input: BuilderStartCall) => `run_${input.idempotencyKey}`,
      { apiVersion: 1 as const },
    );

    expect(failed(await testBuilderStarter(start, { call }))).toEqual([]);
  });

  it("fails a starter that ignores the idempotency key", async () => {
    const start: BuilderStarter = Object.assign(
      async () => crypto.randomUUID(),
      { apiVersion: 1 as const },
    );

    await expect(testBuilderStarter(start, { call })).rejects.toThrow(
      /started a new run/,
    );
  });
});

describe("testTranscriber", () => {
  const transcriber: Transcriber = {
    apiVersion: 1,
    model: "fake-stt",
    transcribe: async (input, options) => {
      options?.signal?.throwIfAborted();
      const bytes = await input.read();

      return {
        segments: [
          { speaker: "A", startMs: 0, endMs: 10, text: `${bytes.length}` },
          { startMs: 10, endMs: 20, text: "two" },
        ],
      };
    },
  };

  it("passes a conforming transcriber", async () => {
    expect(failed(await testTranscriber(transcriber))).toEqual([]);
  });

  it("fails unordered turns, inverted times and ignored signals", async () => {
    const broken: Transcriber = {
      model: "",
      transcribe: async () => ({
        segments: [
          { startMs: 30, endMs: 20, text: "late" },
          { startMs: 0, endMs: 5, text: "early" },
        ],
      }),
    };

    const report = await testTranscriber(broken, {
      input: {
        file: { id: "f", filename: "a.mp3", mediaType: "audio/mpeg" },
        url: "https://example.com/a.mp3",
        read: async () => new Uint8Array([1]),
      },
    }).catch((error: unknown) => error);

    expect(report).toBeInstanceOf(ConformanceError);
  });
});

describe("testNoteTaker", () => {
  const noteTaker: NoteTaker = {
    apiVersion: 1,
    model: "fake-notes",
    summarize: async (input, options) => {
      options?.signal?.throwIfAborted();

      return {
        summary: `${input.transcript.length} turns`,
        actionItems: [{ text: "Send the proposal" }],
      };
    },
  };

  it("passes a conforming note taker", async () => {
    expect(failed(await testNoteTaker(noteTaker))).toEqual([]);
  });

  it("fails an empty summary and ignored signals", async () => {
    const broken: NoteTaker = {
      model: "m",
      summarize: async () => ({ summary: " ", actionItems: [{ text: "" }] }),
    };

    await expect(
      testNoteTaker(broken, { input: { engagement: {}, transcript: [] } }),
    ).rejects.toBeInstanceOf(ConformanceError);
  });
});

describe("testMedicationCatalog", () => {
  const ITEM = {
    name: "Paracetamol",
    unit: "mg",
    codeSystem: "atc",
    code: "N02BE01",
  } as const;

  const catalog: MedicationCatalog = {
    apiVersion: 1,
    search: (_query, options) =>
      options?.signal?.aborted === true
        ? Promise.reject(new Error("aborted"))
        : Promise.resolve([ITEM]),
    get: (code) => Promise.resolve(code === ITEM.code ? ITEM : undefined),
  };

  it("passes a conforming catalog", async () => {
    expect(failed(await testMedicationCatalog(catalog))).toEqual([]);
  });

  const failures = (run: Promise<unknown>): Promise<string[]> =>
    run.then(
      () => [],
      (error: unknown) =>
        error instanceof ConformanceError
          ? failed(error.report)
          : [String(error)],
    );

  it("fails malformed items, a lookup that misses and an ignored signal", async () => {
    const broken: MedicationCatalog = {
      search: () =>
        Promise.resolve([
          { ...ITEM, unit: "" },
          { ...ITEM, name: "" },
        ]),
      get: () => Promise.resolve(ITEM),
    };

    expect(await failures(testMedicationCatalog(broken))).toEqual([
      "has apiVersion 1",
      "returns well-formed items that it can get by code",
      "returns undefined for an unknown code",
      "rejects once aborted",
    ]);

    for (const item of [
      { ...ITEM, codeSystem: "snomed" },
      { ...ITEM, code: "" },
    ]) {
      const odd: MedicationCatalog = {
        ...catalog,
        // SAFETY: an item outside the contract, to test the check.
        search: () => Promise.resolve([item as unknown as typeof ITEM]),
      };

      expect(await failures(testMedicationCatalog(odd))).toEqual([
        "returns well-formed items that it can get by code",
        "rejects once aborted",
      ]);
    }

    const empty: MedicationCatalog = {
      ...catalog,
      search: () => Promise.resolve([]),
    };

    expect(
      await failures(testMedicationCatalog(empty, { query: "x" })),
    ).toEqual([
      "returns well-formed items that it can get by code",
      "rejects once aborted",
    ]);
  });
});

describe("funding claim ports", () => {
  const CLAIM: FundingClaim = {
    id: "00000000-0000-4000-8000-000000000001",
    organizationId: "org",
    funderId: "00000000-0000-4000-8000-000000000002",
    number: "1",
    periodStart: Temporal.PlainDate.from("2026-10-01"),
    periodEnd: Temporal.PlainDate.from("2026-10-31"),
    format: "test-format",
    status: "draft",
    total: money(1500n, "EUR"),
  };

  const LINE: FundingClaimLine = {
    id: "00000000-0000-4000-8000-000000000003",
    claimId: CLAIM.id,
    awardId: "00000000-0000-4000-8000-000000000004",
    productId: "00000000-0000-4000-8000-000000000005",
    units: 2,
    amount: money(1500n, "EUR"),
    status: "pending",
    award: { subject: { type: "client", id: "c1" }, period: "month" },
    product: {
      code: "H126",
      title: "Personal care",
      unit: "hour",
      rate: money(750n, "EUR"),
    },
    deliveries: [],
  };

  const format: FundingClaimFormat = {
    apiVersion: 1,
    key: "test-format",
    render: (claim, lines) => ({
      body: `${claim.number}:${lines.map((line) => line.id).join(",")}`,
      filename: "claim.txt",
      contentType: "text/plain",
    }),
    parseResponse: (body) => ({
      lines: [{ lineId: body, status: "accepted" }],
    }),
  };

  const failures = (run: Promise<unknown>): Promise<string[]> =>
    run.then(
      () => [],
      (error: unknown) =>
        error instanceof ConformanceError
          ? failed(error.report)
          : [String(error)],
    );

  it("passes a conforming format and fails a drifting one", async () => {
    const options = { claim: CLAIM, lines: [LINE], response: LINE.id };
    expect(failed(await testFundingClaimFormat(format, options))).toEqual([]);

    let calls = 0;

    const drifting: FundingClaimFormat = {
      key: "Bad Key",
      render: () => {
        calls += 1;

        return { body: String(calls), filename: "", contentType: "x" };
      },
      parseResponse: () => ({
        lines: [{ lineId: "other", status: "accepted" }],
      }),
    };

    expect(await failures(testFundingClaimFormat(drifting, options))).toEqual([
      "has apiVersion 1",
      "has a well-formed key",
      "renders a claim to the same body every time",
      "reads a response to lines of the claim",
    ]);
  });

  it("passes a conforming channel and fails one that ignores its signal", async () => {
    const rendered = {
      body: "x",
      filename: "x.txt",
      contentType: "text/plain",
    };

    const channel: FundingClaimChannel = {
      apiVersion: 1,
      key: "test",
      send: (_rendered, context) =>
        context.signal?.aborted === true
          ? Promise.reject(new Error("aborted"))
          : Promise.resolve({ externalRef: "ref-1" }),
      poll: () => Promise.resolve(undefined),
    };

    expect(
      failed(
        await testFundingClaimChannel(channel, { claim: CLAIM, rendered }),
      ),
    ).toEqual([]);

    const careless: FundingClaimChannel = {
      apiVersion: 1,
      key: "careless",
      send: () => Promise.resolve({ externalRef: "" }),
    };

    expect(
      await failures(
        testFundingClaimChannel(careless, { claim: CLAIM, rendered }),
      ),
    ).toEqual([
      "sends a claim and polls its reference",
      "rejects once aborted",
    ]);
  });
});
