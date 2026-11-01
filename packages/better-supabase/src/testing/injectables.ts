import type {
  NoteTaker,
  Transcriber,
  TranscriberInput,
} from "../blocks/activities/recordings.ts";
import type { VulnerabilityFeed } from "../blocks/advisories/feed.ts";
import type {
  AiTask,
  AiTaskRun,
  AiTaskRunner,
} from "../blocks/ai-schedules/ai-schedules.ts";
import type {
  CareDecisionContext,
  ClinicalDecisionSupport,
} from "../blocks/clinical-decision-support/clinical-decision-support.ts";
import type { DriveTextFile, TextExtractor } from "../blocks/drive/extract.ts";
import type {
  PrescribedOrder,
  PrescriptionGateway,
  Prescription,
} from "../blocks/e-prescribing/e-prescribing.ts";
import type {
  FundingClaim,
  FundingClaimChannel,
  FundingClaimFormat,
  FundingClaimLine,
  FundingRenderedClaim,
} from "../blocks/funding/funding.ts";
import type { Embedder } from "../blocks/knowledge/knowledge.ts";
import type {
  MedicationCatalog,
  MedicationCatalogItem,
} from "../blocks/medications/medications.ts";
import type { WorkflowGraph } from "../blocks/workflow-editor/graph.ts";
import type {
  BuilderStartCall,
  BuilderStarter,
  GraphCompiler,
} from "../blocks/workflow-editor/workflow-editor.ts";
import type { EveDocumentBackend } from "../eve/eve.ts";
import type { Check, ConformanceReport } from "./conformance.ts";

import { toFhirPrescription } from "../fhir/prescriptions.ts";
import {
  CARE_ALERT_KINDS,
  CARE_ALERT_SEVERITIES,
  CARE_BUILT_IN_SOURCE,
} from "../sql/modules/clinical-decision-support-values.ts";
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
  /** A task the runner can run, as the ai-schedules block passes it. */
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

export interface TestTextExtractorOptions {
  /** A file the extractor reads, with its metadata. Defaults to plain text. */
  readonly file?: Blob;
  readonly meta?: DriveTextFile;
}

const FAKE_TEXT = "The quarterly report is due on Friday.";

const FAKE_FILE: DriveTextFile = {
  nodeId: "node",
  organizationId: "organization",
  name: "report.txt",
  attachmentId: "attachment",
  mimeType: "text/plain",
  size: FAKE_TEXT.length,
};

/**
 * Proves a `TextExtractor` for the drive block has a lowercase name, returns a
 * string or undefined for a file, and answers a type it can't read without a
 * throw. Pass a real file in `file` and `meta` for the type it reads.
 */
export function testTextExtractor(
  extractor: TextExtractor,
  options: TestTextExtractorOptions = {},
): Promise<ConformanceReport> {
  const file = options.file ?? new Blob([FAKE_TEXT], { type: "text/plain" });
  const meta = options.meta ?? FAKE_FILE;

  return conform(`TextExtractor "${extractor.name}"`, [
    hasApiVersion(extractor),
    [
      "names itself",
      () => {
        expect(
          /^[a-z][a-z0-9_.-]{0,62}$/u.test(extractor.name),
          "name must be lowercase letters, digits, dots, dashes or underscores",
        );
      },
    ],
    [
      "returns the file's text or nothing",
      async () => {
        const text = await extractor.extract(file, meta);
        expect(
          text === undefined || typeof text === "string",
          `extract returned ${typeof text}`,
        );
      },
    ],
    [
      "answers an unknown type without a throw",
      async () => {
        const text = await extractor.extract(
          new Blob([new Uint8Array([0, 1, 2, 3])]),
          { ...meta, name: "unknown.bin", mimeType: "application/x-bsb-test" },
        );

        expect(
          text === undefined || typeof text === "string",
          "an unknown type must return undefined or its text",
        );
      },
    ],
  ]);
}

export interface TestMedicationCatalogOptions {
  /** A query the catalog has results for. Default `paracetamol`. */
  readonly query?: string;
  /** A code the catalog has no item for. Default `does-not-exist`. */
  readonly unknownCode?: string;
}

const CODE_SYSTEMS = new Set(["gtin", "hpk", "atc", "rxnorm", "custom"]);

const itemIssue = (item: MedicationCatalogItem): string | undefined => {
  if (typeof item.name !== "string" || item.name.trim() === "") {
    return "every item needs a name";
  }

  if (typeof item.unit !== "string" || item.unit.trim() === "") {
    return `${item.name} needs a unit`;
  }

  if (!CODE_SYSTEMS.has(item.codeSystem)) {
    return `${item.name} has code system ${item.codeSystem}`;
  }

  return typeof item.code === "string" && item.code !== ""
    ? undefined
    : `${item.name} needs a code`;
};

/**
 * Proves a `MedicationCatalog` for the medications block returns well-formed
 * items for `query`, gets each by its code, returns `undefined` for an unknown
 * code, and rejects once its signal is aborted. It calls the real catalog.
 */
export function testMedicationCatalog(
  catalog: MedicationCatalog,
  options: TestMedicationCatalogOptions = {},
): Promise<ConformanceReport> {
  const query = options.query ?? "paracetamol";
  const unknown = options.unknownCode ?? "does-not-exist";

  return conform("MedicationCatalog", [
    hasApiVersion(catalog),
    [
      "returns well-formed items that it can get by code",
      async () => {
        const items = await catalog.search(query);
        expect(items.length > 0, `no items for "${query}"`);

        for (const item of items) {
          const issue = itemIssue(item);
          expect(issue === undefined, issue ?? "");
        }

        const [first] = items;

        if (first !== undefined) {
          const got = await catalog.get(first.code);
          expect(got?.code === first.code, `get(${first.code}) missed it`);
        }
      },
    ],
    [
      "returns undefined for an unknown code",
      async () => {
        const got = await catalog.get(unknown);
        expect(got === undefined, `get(${unknown}) returned an item`);
      },
    ],
    [
      "rejects once aborted",
      async () => {
        expect(
          await rejects(() =>
            catalog.search(query, { signal: AbortSignal.abort() }),
          ),
          "search must reject when its signal is aborted",
        );
      },
    ],
  ]);
}

export interface TestFundingClaimFormatOptions {
  /** A draft claim as `get_funding_claim` returns it, without its lines. */
  readonly claim: FundingClaim;
  /** The claim's lines. */
  readonly lines: readonly FundingClaimLine[];
  /**
   * A return message from the funder for `claim`, to prove `parseResponse`
   * answers only for the claim's lines. Skipped when left out.
   */
  readonly response?: string;
}

const FUNDING_FORMAT_KEY = /^[a-z0-9][a-z0-9_.-]{0,62}$/;

/**
 * Proves a `FundingClaimFormat` for the funding block has a key
 * `build_funding_claim` accepts, renders `options.claim` to the same non-empty
 * body twice, and reads `options.response` to lines of the claim.
 */
export function testFundingClaimFormat(
  format: FundingClaimFormat,
  options: TestFundingClaimFormatOptions,
): Promise<ConformanceReport> {
  const { claim, lines } = options;
  const context = { organizationId: claim.organizationId };

  const checks: Check[] = [
    hasApiVersion(format),
    [
      "has a well-formed key",
      () => {
        expect(
          FUNDING_FORMAT_KEY.test(format.key),
          `key ${format.key} must match ${FUNDING_FORMAT_KEY.source}`,
        );
      },
    ],
    [
      "renders a claim to the same body every time",
      async () => {
        const first = await format.render(claim, lines, context);
        expect(first.body !== "", "the body must not be empty");
        expect(first.filename.trim() !== "", "a filename is required");
        expect(first.contentType.trim() !== "", "a content type is required");
        const again = await format.render(claim, lines, context);
        expect(again.body === first.body, "a second render changed the body");
      },
    ],
  ];

  const { response } = options;

  if (response !== undefined) {
    checks.push([
      "reads a response to lines of the claim",
      async () => {
        const parsed = await format.parseResponse(response);
        const ids = new Set(lines.map((line) => line.id));

        for (const line of parsed.lines) {
          const status: unknown = line.status;

          expect(
            ids.has(line.lineId),
            `line ${line.lineId} isn't on the claim`,
          );
          expect(
            status === "accepted" || status === "rejected",
            `line ${line.lineId} has status ${String(status)}`,
          );
        }
      },
    ]);
  }

  return conform(`FundingClaimFormat "${format.key}"`, checks);
}

export interface TestFundingClaimChannelOptions {
  /** The claim the rendered body belongs to. */
  readonly claim: FundingClaim;
  /** A rendered test claim the channel's test environment accepts. */
  readonly rendered: FundingRenderedClaim;
}

/**
 * Proves a `FundingClaimChannel` sends a rendered claim and returns a
 * reference, polls that reference to a body or `undefined`, and rejects once
 * its signal is aborted. It sends for real: point it at a test environment.
 */
export function testFundingClaimChannel(
  channel: FundingClaimChannel,
  options: TestFundingClaimChannelOptions,
): Promise<ConformanceReport> {
  const { claim, rendered } = options;
  const context = { organizationId: claim.organizationId, claim };

  return conform(`FundingClaimChannel "${channel.key}"`, [
    hasApiVersion(channel),
    [
      "sends a claim and polls its reference",
      async () => {
        const sent = await channel.send(rendered, context);
        expect(
          typeof sent.externalRef === "string" && sent.externalRef !== "",
          "send must return a non-empty externalRef",
        );

        if (channel.poll !== undefined) {
          const body = await channel.poll(sent.externalRef, context);
          expect(
            body === undefined || typeof body === "string",
            "poll must return a body or undefined",
          );
        }
      },
    ],
    [
      "rejects once aborted",
      async () => {
        expect(
          await rejects(() =>
            channel.send(rendered, { ...context, signal: AbortSignal.abort() }),
          ),
          "send must reject when its signal is aborted",
        );
      },
    ],
  ]);
}

export interface TestClinicalDecisionSupportOptions {
  /** A context the engine answers; use one with orders it raises alerts for. */
  readonly context: CareDecisionContext;
}

/**
 * Proves a `ClinicalDecisionSupport` engine has a key the block accepts,
 * answers `options.context` with well-formed alerts, answers it the same way
 * twice (so fingerprints stay stable and a decision survives re-evaluation),
 * and answers a context without medications.
 */
export function testClinicalDecisionSupport(
  engine: ClinicalDecisionSupport,
  options: TestClinicalDecisionSupportOptions,
): Promise<ConformanceReport> {
  const { context } = options;

  const checks: Check[] = [
    hasApiVersion(engine),
    [
      "has a key the block accepts",
      () => {
        expect(
          engine.key.trim() !== "" &&
            engine.key.length <= 100 &&
            engine.key !== CARE_BUILT_IN_SOURCE,
          `key "${engine.key}" must be 1 to 100 characters and not "${CARE_BUILT_IN_SOURCE}"`,
        );
      },
    ],
    [
      "returns well-formed alerts",
      async () => {
        const alerts = await engine.evaluate(context, {});

        for (const alert of alerts) {
          const kind: unknown = alert.kind ?? "other";
          const severity: unknown = alert.severity ?? "warning";

          expect(
            alert.message.trim() !== "" && alert.message.length <= 1000,
            "a message of 1 to 1000 characters is required",
          );
          expect(
            CARE_ALERT_KINDS.some((known) => known === kind),
            `kind ${String(kind)} is unknown`,
          );
          expect(
            CARE_ALERT_SEVERITIES.some((known) => known === severity),
            `severity ${String(severity)} is unknown`,
          );
          expect(
            (alert.fingerprint ?? "").length <= 200,
            "a fingerprint has at most 200 characters",
          );
        }
      },
    ],
    [
      "answers the same context with the same fingerprints",
      async () => {
        const fingerprints = async (): Promise<string> =>
          JSON.stringify(
            (await engine.evaluate(context, {}))
              .map((alert) => alert.fingerprint ?? alert.message)
              .toSorted(),
          );

        const first = await fingerprints();
        const second = await fingerprints();

        expect(
          first === second,
          "a second evaluation returned different alerts",
        );
      },
    ],
    [
      "answers a context without medications",
      async () => {
        const alerts = await engine.evaluate(
          { ...context, medications: [], observations: [], consents: [] },
          {},
        );

        expect(Array.isArray(alerts), "evaluate must return an array");
      },
    ],
  ];

  return conform(`ClinicalDecisionSupport "${engine.key}"`, checks);
}

export interface TestPrescriptionGatewayOptions {
  /** A signed prescription the gateway delivers. */
  readonly prescription: Prescription & { readonly order: PrescribedOrder };
}

/**
 * Proves a `PrescriptionGateway` has a key the block accepts, delivers
 * `options.prescription` with its FHIR R4 `MedicationRequest` and answers with
 * a reference of at most 200 characters (or none), delivers it twice without
 * throwing (a retry after a failure is normal), and, when it can cancel,
 * cancels a prescription it took.
 */
export function testPrescriptionGateway(
  gateway: PrescriptionGateway,
  options: TestPrescriptionGatewayOptions,
): Promise<ConformanceReport> {
  const { prescription } = options;
  const medicationRequest = toFhirPrescription(prescription);

  const checks: Check[] = [
    hasApiVersion(gateway),
    [
      "has a key the block accepts",
      () => {
        expect(
          gateway.key.trim() !== "" && gateway.key.length <= 100,
          `key "${gateway.key}" must be 1 to 100 characters`,
        );
      },
    ],
    [
      "delivers a prescription and answers a bounded reference",
      async () => {
        const receipt = await gateway.deliver(
          { prescription, medicationRequest },
          {},
        );

        expect(
          (receipt.reference ?? "").length <= 200,
          "a reference has at most 200 characters",
        );
      },
    ],
    [
      "delivers the same prescription twice",
      async () => {
        await gateway.deliver({ prescription, medicationRequest }, {});
        await gateway.deliver({ prescription, medicationRequest }, {});
      },
    ],
  ];

  if (gateway.cancel !== undefined) {
    checks.push([
      "cancels a prescription it took",
      async () => {
        await gateway.cancel?.({ prescription, reason: "conformance" }, {});
      },
    ]);
  }

  return conform(`PrescriptionGateway "${gateway.key}"`, checks);
}

export interface TestVulnerabilityFeedOptions {
  /** A CVE id the feed knows in all three sources, such as `CVE-2021-44228`. */
  readonly cveId: string;
  /** An id OSV has no record of. Defaults to one that no database assigns. */
  readonly unknownId?: string;
}

/**
 * Proves a `VulnerabilityFeed` for the advisories block targets API 1, has a
 * name the block accepts, returns OSV records with the fields the block stores
 * (and nothing for an unknown id), scores EPSS between 0 and 1 for a known CVE
 * and none for an empty list, and returns CISA KEV entries keyed by CVE id with
 * a `YYYY-MM-DD` date. It calls the real sources.
 */
export function testVulnerabilityFeed(
  feed: VulnerabilityFeed,
  options: TestVulnerabilityFeedOptions,
): Promise<ConformanceReport> {
  const { cveId } = options;
  const unknownId = options.unknownId ?? "BSB-TEST-0000-0000";
  const day = /^\d{4}-\d{2}-\d{2}$/u;

  const checks: Check[] = [
    hasApiVersion(feed),
    [
      "has a name the block accepts",
      () => {
        expect(
          /^[a-z][a-z0-9_-]{0,62}$/u.test(feed.name),
          `name "${feed.name}" must be lowercase letters, digits, "-" or "_"`,
        );
      },
    ],
    [
      "returns an OSV record with its id, aliases and affected packages",
      async () => {
        const found = await feed.osv(cveId);

        expect(found.ok, `osv(${cveId}) failed`);
        const record = found.data;

        expect(record !== undefined, `osv(${cveId}) found no record`);
        expect(record.id.trim() !== "", "the record has no id");
        expect(Array.isArray(record.aliases), "aliases must be a list");
        expect(
          record.affectedPurls.every((purl) => purl.startsWith("pkg:")),
          "affectedPurls must be package URLs",
        );
      },
    ],
    [
      "answers undefined for an id it does not know",
      async () => {
        const found = await feed.osv(unknownId);

        expect(found.ok, `osv(${unknownId}) failed`);
        expect(found.data === undefined, `osv(${unknownId}) must find nothing`);
      },
    ],
    [
      "scores a known CVE between 0 and 1 and an empty list as nothing",
      async () => {
        const empty = await feed.epss([]);

        expect(empty.ok, "epss([]) failed");
        expect(
          Object.keys(empty.data).length === 0,
          "epss([]) must return no scores",
        );

        const scores = await feed.epss([cveId]);

        expect(scores.ok, `epss(${cveId}) failed`);

        const score = scores.data[cveId];

        expect(score !== undefined, `epss(${cveId}) has no score`);
        expect(
          score.score >= 0 &&
            score.score <= 1 &&
            score.percentile >= 0 &&
            score.percentile <= 1 &&
            day.test(score.date),
          "a score and a percentile are between 0 and 1, and the date is YYYY-MM-DD",
        );
      },
    ],
    [
      "returns the KEV catalog by CVE id",
      async () => {
        const catalog = await feed.kev();

        expect(catalog.ok, "kev() failed");

        for (const [id, entry] of Object.entries(catalog.data)) {
          expect(
            entry.cveId === id && day.test(entry.dateAdded),
            `entry ${id} must carry its CVE id and a YYYY-MM-DD dateAdded`,
          );
        }
      },
    ],
  ];

  return conform(`VulnerabilityFeed "${feed.name}"`, checks);
}
