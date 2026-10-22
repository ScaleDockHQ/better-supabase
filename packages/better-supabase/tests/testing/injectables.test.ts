import { describe, expect, it } from "vitest";

import type {
  AiTask,
  AiTaskRun,
  AiTaskRunner,
} from "../../src/blocks/ai-tasks/ai-tasks.ts";
import type {
  NoteTaker,
  Transcriber,
} from "../../src/blocks/engagements/recordings.ts";
import type { Embedder } from "../../src/blocks/knowledge/knowledge.ts";
import type { WorkflowGraph } from "../../src/blocks/workflow-builder/graph.ts";
import type {
  BuilderStartCall,
  BuilderStarter,
  GraphCompiler,
} from "../../src/blocks/workflow-builder/workflow-builder.ts";

import { injectableOf } from "../../src/core/block-helpers.ts";
import {
  ConformanceError,
  testAiTaskRunner,
  testBuilderStarter,
  testEmbedder,
  testGraphCompiler,
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
