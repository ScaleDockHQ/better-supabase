import type {
  AiTask,
  AiTaskRun,
  AiTaskRunner,
} from "../blocks/ai-tasks/ai-tasks.ts";
import type {
  NoteTaker,
  Transcriber,
  TranscriberInput,
} from "../blocks/engagements/recordings.ts";
import type { Embedder } from "../blocks/knowledge/knowledge.ts";
import type { WorkflowGraph } from "../blocks/workflow-builder/graph.ts";
import type {
  BuilderStartCall,
  BuilderStarter,
  GraphCompiler,
} from "../blocks/workflow-builder/workflow-builder.ts";
import type { EveDocumentBackend } from "../eve/eve.ts";
import type { Check, ConformanceReport } from "./conformance.ts";

import { conform, expect, same } from "./conformance.ts";

const hasApiVersion = (subject: { readonly apiVersion?: unknown }): Check => [
  "has apiVersion 1",
  () => {
    const version: unknown = subject.apiVersion;
    expect(version === 1, `apiVersion is ${String(version)}, not 1`);
  },
];

const rejects = async (run: () => Promise<unknown>): Promise<boolean> => {
  try {
    await run();

    return false;
  } catch {
    return true;
  }
};

export interface TestEmbedderOptions {
  /** The texts to embed. Defaults to two short sentences. */
  readonly values?: readonly string[];
}

/**
 * Proves an `Embedder` for the knowledge and memory blocks names its model,
 * embeds an empty list to nothing, and returns one finite vector per value, all
 * of the same length on every call. It calls the real model.
 */
export function testEmbedder(
  embedder: Embedder,
  options: TestEmbedderOptions = {},
): Promise<ConformanceReport> {
  const values = options.values ?? ["The first text.", "A second text."];

  return conform(`Embedder "${embedder.model}"`, [
    hasApiVersion(embedder),
    [
      "names its model",
      () => {
        expect(
          typeof embedder.model === "string" && embedder.model !== "",
          "model must be a non-empty string",
        );
      },
    ],
    [
      "embeds nothing to nothing",
      async () => {
        const vectors = await embedder.embed([]);
        expect(vectors.length === 0, `got ${vectors.length} vectors`);
      },
    ],
    [
      "returns one finite vector per value, of one length",
      async () => {
        const first = await embedder.embed(values);
        expect(
          first.length === values.length,
          `got ${first.length} vectors for ${values.length} values`,
        );
        const size = first[0]?.length ?? 0;
        expect(size > 0, "vectors must not be empty");
        expect(
          first.every(
            (vector) => vector.length === size && vector.every(Number.isFinite),
          ),
          "vectors must share one length and hold finite numbers",
        );
        const [again] = await embedder.embed(values.slice(0, 1));
        expect(again?.length === size, "a second call changed the length");
      },
    ],
  ]);
}

export interface TestAiTaskRunnerOptions {
  /** A task the runner can run, as the ai-tasks block passes it. */
  readonly task: AiTask;
  /** The claimed run for `task`. */
  readonly run: AiTaskRun;
}

/**
 * Proves an `AiTaskRunner` resolves with nothing or a chat id and stops when
 * its signal is already aborted. It runs `options.task` for real.
 */
export function testAiTaskRunner(
  runner: AiTaskRunner,
  options: TestAiTaskRunnerOptions,
): Promise<ConformanceReport> {
  const { task, run } = options;

  return conform("AiTaskRunner", [
    hasApiVersion(runner),
    [
      "resolves with nothing or a chat id",
      async () => {
        const result: unknown = await runner(
          task,
          run,
          new AbortController().signal,
        );

        expect(
          result === undefined ||
            (typeof result === "object" &&
              result !== null &&
              (!("chatId" in result) ||
                result.chatId === undefined ||
                typeof result.chatId === "string")),
          "must resolve with undefined or { chatId?: string }",
        );
      },
    ],
    [
      "stops on an aborted signal",
      async () => {
        expect(
          await rejects(() => runner(task, run, AbortSignal.abort())),
          "resolved although the signal was aborted",
        );
      },
    ],
  ]);
}

export interface TestGraphCompilerOptions {
  /** A valid graph for the compiler's engine. */
  readonly graph: WorkflowGraph;
}

/**
 * Proves a `GraphCompiler` returns a JSON value (stored with the published
 * version), compiles the same graph to the same value and leaves the graph
 * unchanged.
 */
export function testGraphCompiler(
  compile: GraphCompiler,
  options: TestGraphCompilerOptions,
): Promise<ConformanceReport> {
  const { graph } = options;

  return conform("GraphCompiler", [
    hasApiVersion(compile),
    [
      "returns a JSON value",
      async () => {
        const compiled: unknown = await compile(graph);

        if (compiled === undefined) {
          return;
        }

        const json = JSON.stringify(compiled);
        expect(
          same(JSON.parse(json), compiled),
          "the compiled form must survive a JSON round trip",
        );
      },
    ],
    [
      "compiles one graph to one value, without changing it",
      async () => {
        const before = structuredClone(graph);
        const first: unknown = await compile(graph);
        const second: unknown = await compile(graph);
        expect(same(first, second), "two compiles of one graph differ");
        expect(same(graph, before), "compile changed the graph");
      },
    ],
  ]);
}

export interface TestBuilderStarterOptions {
  /** A start call the engine can run. */
  readonly call: BuilderStartCall;
}

/**
 * Proves a `BuilderStarter` returns a run id and returns the same id when the
 * same idempotency key starts again. It starts real runs.
 */
export function testBuilderStarter(
  start: BuilderStarter,
  options: TestBuilderStarterOptions,
): Promise<ConformanceReport> {
  const { call } = options;

  return conform("BuilderStarter", [
    hasApiVersion(start),
    [
      "returns one run id per idempotency key",
      async () => {
        const first = await start(call);
        expect(
          typeof first === "string" && first !== "",
          "must resolve with a non-empty run id",
        );
        const again = await start(call);
        expect(again === first, "a repeated idempotency key started a new run");
      },
    ],
  ]);
}

export interface TestEveDocumentBackendOptions {
  /** The document key to write. Defaults to a random `conformance/` key. */
  readonly key?: string;
}

/**
 * Proves an `EveDocumentBackend` reads a missing document as `null`, creates
 * one with `expectedVersion: null`, refuses a stale version and moves the
 * version on every write. It writes `options.key` on the real store.
 */
export function testEveDocumentBackend(
  backend: EveDocumentBackend,
  options: TestEveDocumentBackendOptions = {},
): Promise<ConformanceReport> {
  const key = options.key ?? `conformance/${crypto.randomUUID()}`;

  return conform("EveDocumentBackend", [
    hasApiVersion(backend),
    [
      "creates, reads and updates a document by version",
      async () => {
        expect(
          (await backend.read({ key })) === null,
          "a missing document must read as null",
        );

        const created = await backend.write({
          key,
          content: "one",
          expectedVersion: null,
        });

        const read = await backend.read({ key });
        expect(
          read?.content === "one" && read.version === created.version,
          "read must return the written content and version",
        );

        const updated = await backend.write({
          key,
          content: "two",
          expectedVersion: created.version,
        });

        expect(
          updated.version !== created.version,
          "a write must change the version",
        );
        expect(
          await rejects(() =>
            backend.write({
              key,
              content: "three",
              expectedVersion: created.version,
            }),
          ),
          "a write with a stale version must throw",
        );
        expect(
          (await backend.read({ key }))?.content === "two",
          "a refused write changed the document",
        );
      },
    ],
  ]);
}

export interface TestTranscriberOptions {
  /** The recording to transcribe. Defaults to a fake file with no bytes. */
  readonly input?: TranscriberInput;
}

const FAKE_RECORDING: TranscriberInput = {
  file: { id: "recording", filename: "call.webm", mediaType: "audio/webm" },
  url: "https://example.com/call.webm",
  read: () => Promise.resolve(new Uint8Array()),
};

/**
 * Proves a `Transcriber` for the engagements block names its model, returns
 * speaker turns in order with `startMs` at most `endMs` and text on each, and
 * rejects once its signal is aborted. Pass a real recording in `input` to call
 * the real provider.
 */
export function testTranscriber(
  transcriber: Transcriber,
  options: TestTranscriberOptions = {},
): Promise<ConformanceReport> {
  const input = options.input ?? FAKE_RECORDING;

  return conform(`Transcriber "${transcriber.model}"`, [
    hasApiVersion(transcriber),
    [
      "names its model",
      () => {
        expect(
          typeof transcriber.model === "string" && transcriber.model !== "",
          "model must be a non-empty string",
        );
      },
    ],
    [
      "returns ordered speaker turns",
      async () => {
        const { segments } = await transcriber.transcribe(input);
        let last = 0;

        for (const segment of segments) {
          expect(
            typeof segment.text === "string",
            "every segment needs its text",
          );
          expect(
            Number.isFinite(segment.startMs) &&
              Number.isFinite(segment.endMs) &&
              segment.startMs <= segment.endMs,
            `segment ${segment.startMs}-${segment.endMs} must start before it ends`,
          );
          expect(
            segment.startMs >= last,
            "segments must be ordered by startMs",
          );
          last = segment.startMs;
        }
      },
    ],
    [
      "rejects once aborted",
      async () => {
        expect(
          await rejects(() =>
            transcriber.transcribe(input, { signal: AbortSignal.abort() }),
          ),
          "transcribe must reject when its signal is aborted",
        );
      },
    ],
  ]);
}

export interface TestNoteTakerOptions {
  /** The engagement and transcript to summarize. Defaults to a short call. */
  readonly input?: Parameters<NoteTaker["summarize"]>[0];
}

const FAKE_CALL: Parameters<NoteTaker["summarize"]>[0] = {
  engagement: { id: "engagement", kind: "call", title: "Intro call" },
  transcript: [
    {
      recordingId: "recording",
      position: 1,
      speaker: "Speaker 1",
      startMs: 0,
      endMs: 4000,
      text: "Can you send the proposal by Friday?",
    },
    {
      recordingId: "recording",
      position: 2,
      speaker: "Speaker 2",
      startMs: 4000,
      endMs: 7000,
      text: "Yes, I will send it on Thursday.",
    },
  ],
};

/**
 * Proves a `NoteTaker` for the engagements block names its model, returns a
 * non-empty summary with well-formed action items, and rejects once its signal
 * is aborted. It calls the real model.
 */
export function testNoteTaker(
  noteTaker: NoteTaker,
  options: TestNoteTakerOptions = {},
): Promise<ConformanceReport> {
  const input = options.input ?? FAKE_CALL;

  return conform(`NoteTaker "${noteTaker.model}"`, [
    hasApiVersion(noteTaker),
    [
      "names its model",
      () => {
        expect(
          typeof noteTaker.model === "string" && noteTaker.model !== "",
          "model must be a non-empty string",
        );
      },
    ],
    [
      "writes a summary and action items",
      async () => {
        const notes = await noteTaker.summarize(input);
        expect(
          typeof notes.summary === "string" && notes.summary.trim() !== "",
          "summary must be a non-empty string",
        );
        expect(
          (notes.actionItems ?? []).every(
            (item) => typeof item.text === "string" && item.text !== "",
          ),
          "every action item needs its text",
        );
      },
    ],
    [
      "rejects once aborted",
      async () => {
        expect(
          await rejects(() =>
            noteTaker.summarize(input, { signal: AbortSignal.abort() }),
          ),
          "summarize must reject when its signal is aborted",
        );
      },
    ],
  ]);
}
