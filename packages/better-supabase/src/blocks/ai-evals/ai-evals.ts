import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { PromptfooConfig } from "./promptfoo.ts";
import type { EvalScorer, ScorerDescription } from "./scorers.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  instantOf,
  isRecord,
  nullableInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { toPromptfooConfig } from "./promptfoo.ts";
import { describeScorer } from "./scorers.ts";

export type EvalRunStatus = "running" | "completed" | "failed" | "cancelled";

export interface EvalDataset {
  readonly id: string;
  readonly organizationId: string | undefined;
  readonly name: string;
  readonly description: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface EvalItem {
  readonly id: string;
  readonly datasetId: string;
  readonly input: unknown;
  readonly expected: unknown;
  readonly metadata: Readonly<Record<string, unknown>>;
  /** The ai-chat chat and message an item was taken from. */
  readonly sourceChatId: string | undefined;
  readonly sourceMessageId: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** An item to add: an input and, when known, the expected output. */
export interface EvalItemInput {
  readonly input: unknown;
  readonly expected?: unknown;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** The score one scorer gave one item. */
export interface EvalScore {
  readonly score: number;
  readonly passed: boolean;
  readonly reason?: string;
}

export interface EvalSummary {
  readonly total: number;
  readonly passed: number;
  readonly failed: number;
  readonly errored: number;
  readonly passRate: number;
  readonly scorers: Readonly<
    Record<string, { readonly avg: number; readonly passRate: number }>
  >;
}

export interface EvalRun {
  readonly id: string;
  readonly datasetId: string;
  readonly organizationId: string | undefined;
  /** The `prompts` block's name and version the run used. */
  readonly promptName: string;
  readonly promptVersion: number;
  readonly model: string;
  readonly scorers: readonly ScorerDescription[];
  readonly status: EvalRunStatus;
  readonly summary: EvalSummary | undefined;
  readonly createdAt: Temporal.Instant;
  readonly finishedAt: Temporal.Instant | undefined;
}

export interface EvalResult {
  readonly runId: string;
  readonly itemId: string;
  readonly output: string | undefined;
  readonly scores: Readonly<Record<string, EvalScore>>;
  readonly passed: boolean;
  readonly error: string | undefined;
  readonly latencyMs: number | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface EvalComparisonItem {
  readonly itemId: string;
  readonly baseScore: number | undefined;
  readonly candidateScore: number | undefined;
  readonly baseOutput?: string | undefined;
  readonly candidateOutput?: string | undefined;
}

/** The difference between two runs of one dataset. */
export interface EvalComparison {
  readonly base: EvalSummary;
  readonly candidate: EvalSummary;
  /** Candidate pass rate minus base pass rate; negative is a regression. */
  readonly passRateDelta: number;
  /** Items the base run passed and the candidate did not. */
  readonly regressions: readonly EvalComparisonItem[];
  readonly improvements: readonly EvalComparisonItem[];
  readonly unchanged: number;
  /** Items only one of the runs has a result for. */
  readonly missing: number;
}

export interface AiEvalsOptions extends BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AiEvals>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Calls as the service role: items and outputs can hold user content. */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface EvalExportOptions {
  /** The prompt template to test; read it with the `prompts` block. */
  readonly prompt: string;
  /** The promptfoo provider id, such as `openai:gpt-4.1-mini`. */
  readonly model: string;
  readonly scorers: readonly (EvalScorer | ScorerDescription)[];
  readonly description?: string;
}

export interface AiEvals {
  readonly datasets: {
    /** Creates a dataset, or returns the one with that name. */
    create(
      name: string,
      options?: {
        readonly organizationId?: string;
        readonly description?: string;
      },
    ): AsyncResult<EvalDataset>;
  };
  readonly items: {
    /** Adds items and returns how many. */
    add(
      datasetId: string,
      items: readonly EvalItemInput[],
    ): AsyncResult<number>;
    /**
     * Copies rated ai-chat replies into the dataset (needs the `ai-chat`
     * block): the user message is the input, and a thumbs up keeps the reply as
     * the expected output. Replies already in the dataset are skipped. Returns
     * how many were added.
     */
    addFromFeedback(
      datasetId: string,
      options?: {
        /** Default `-1`: the replies users rated down. */
        readonly rating?: -1 | 1;
        readonly since?: Temporal.Instant;
        readonly limit?: number;
      },
    ): AsyncResult<number>;
    /** Items in id order. `pendingRun` leaves out the items a run already has. */
    list(
      datasetId: string,
      options?: {
        readonly pendingRun?: string;
        readonly after?: string;
        readonly limit?: number;
      },
    ): AsyncResult<readonly EvalItem[]>;
  };
  readonly runs: {
    /** Starts a run against a prompt version and model. */
    create(
      datasetId: string,
      options: {
        readonly promptName: string;
        readonly promptVersion: number;
        readonly model: string;
        readonly scorers?: readonly (EvalScorer | ScorerDescription)[];
      },
    ): AsyncResult<EvalRun>;
    get(runId: string): AsyncResult<EvalRun | undefined>;
    /** The runs of a dataset, newest first. */
    list(
      datasetId: string,
      options?: { readonly limit?: number },
    ): AsyncResult<readonly EvalRun[]>;
    /**
     * Stores one item's output and scores; a repeat replaces the earlier
     * result.
     */
    record(
      runId: string,
      itemId: string,
      result: {
        readonly output?: string;
        readonly scores?: Readonly<Record<string, EvalScore>>;
        readonly error?: string;
        readonly latencyMs?: number;
      },
    ): AsyncResult<EvalResult>;
    results(
      runId: string,
      options?: {
        readonly onlyFailed?: boolean;
        readonly after?: string;
        readonly limit?: number;
      },
    ): AsyncResult<readonly EvalResult[]>;
    /** Closes the run and stores its summary. */
    finish(
      runId: string,
      status?: Exclude<EvalRunStatus, "running">,
    ): AsyncResult<EvalRun>;
    /**
     * Compares two runs of one dataset. `scoreDrop` also counts an item as
     * regressed when its average score fell by more than that.
     */
    compare(
      baseRunId: string,
      candidateRunId: string,
      options?: { readonly scoreDrop?: number },
    ): AsyncResult<EvalComparison>;
  };
  /**
   * A promptfoo config (JSON) with one test per item of the dataset, so the
   * same dataset runs in `promptfoo eval`.
   */
  exportPromptfoo(
    datasetId: string,
    options: EvalExportOptions,
  ): AsyncResult<PromptfooConfig>;
}

/** The page size `exportPromptfoo` reads items in; the module caps pages at 1000. */
const EXPORT_PAGE = 500;

function datasetOf(value: unknown): EvalDataset {
  const row = recordOf(value, "eval_datasets");

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    createdAt: instantOf(row["created_at"]),
  };
}

function itemOf(value: unknown): EvalItem {
  const row = recordOf(value, "eval_items");
  const metadata = row["metadata"];

  return {
    id: textOf(row["id"]),
    datasetId: textOf(row["dataset_id"]),
    input: row["input"],
    expected: row["expected"] ?? undefined,
    metadata: isRecord(metadata) ? metadata : {},
    sourceChatId: optionalText(row["source_chat_id"]),
    sourceMessageId: optionalText(row["source_message_id"]),
    createdAt: instantOf(row["created_at"]),
  };
}

function summaryOf(value: unknown): EvalSummary | undefined {
  if (!isRecord(value)) {
    return;
  }

  const scorers = isRecord(value["scorers"]) ? value["scorers"] : {};

  return {
    total: Number(value["total"] ?? 0),
    passed: Number(value["passed"] ?? 0),
    failed: Number(value["failed"] ?? 0),
    errored: Number(value["errored"] ?? 0),
    passRate: Number(value["passRate"] ?? 0),
    scorers: Object.fromEntries(
      Object.entries(scorers).flatMap(([name, entry]) =>
        isRecord(entry)
          ? [
              [
                name,
                {
                  avg: Number(entry["avg"] ?? 0),
                  passRate: Number(entry["passRate"] ?? 0),
                },
              ],
            ]
          : [],
      ),
    ),
  };
}

const EMPTY_SUMMARY: EvalSummary = {
  total: 0,
  passed: 0,
  failed: 0,
  errored: 0,
  passRate: 0,
  scorers: {},
};

function describedOf(value: unknown): ScorerDescription[] {
  return Array.isArray(value)
    ? value.flatMap((entry): ScorerDescription[] => {
        if (!isRecord(entry)) {
          return [];
        }

        const kind = entry["kind"];

        if (
          kind !== "exact_match" &&
          kind !== "json_schema" &&
          kind !== "llm_judge"
        ) {
          return [];
        }

        const schema = entry["jsonSchema"];

        return [
          {
            name: textOf(entry["name"]),
            kind,
            ...(typeof entry["criteria"] === "string"
              ? { criteria: entry["criteria"] }
              : {}),
            ...(typeof entry["threshold"] === "number"
              ? { threshold: entry["threshold"] }
              : {}),
            ...(isRecord(schema) ? { jsonSchema: schema } : {}),
          },
        ];
      })
    : [];
}

function runOf(value: unknown): EvalRun {
  const row = recordOf(value, "eval_runs");
  const status = row["status"];

  return {
    id: textOf(row["id"]),
    datasetId: textOf(row["dataset_id"]),
    organizationId: optionalText(row["organization_id"]),
    promptName: textOf(row["prompt_name"]),
    promptVersion: Number(row["prompt_version"]),
    model: textOf(row["model"]),
    scorers: describedOf(row["scorers"]),
    status:
      status === "completed" || status === "failed" || status === "cancelled"
        ? status
        : "running",
    summary: summaryOf(row["summary"]),
    createdAt: instantOf(row["created_at"]),
    finishedAt: nullableInstant(row["finished_at"]) ?? undefined,
  };
}

function scoresOf(value: unknown): Record<string, EvalScore> {
  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([name, entry]) =>
      isRecord(entry)
        ? [
            [
              name,
              {
                score: Number(entry["score"] ?? 0),
                passed: entry["passed"] === true,
                ...(typeof entry["reason"] === "string"
                  ? { reason: entry["reason"] }
                  : {}),
              },
            ],
          ]
        : [],
    ),
  );
}

function resultOf(value: unknown): EvalResult {
  const row = recordOf(value, "eval_results");

  return {
    runId: textOf(row["run_id"]),
    itemId: textOf(row["item_id"]),
    output: optionalText(row["output"]),
    scores: scoresOf(row["scores"]),
    passed: row["passed"] === true,
    error: optionalText(row["error"]),
    latencyMs:
      typeof row["latency_ms"] === "number" ? row["latency_ms"] : undefined,
    createdAt: instantOf(row["created_at"]),
  };
}

function comparisonItemsOf(value: unknown, fn: string): EvalComparisonItem[] {
  return recordsOf(value, fn).map((row) => ({
    itemId: textOf(row["item_id"]),
    baseScore:
      row["base_score"] === null || row["base_score"] === undefined
        ? undefined
        : Number(row["base_score"]),
    candidateScore:
      row["candidate_score"] === null || row["candidate_score"] === undefined
        ? undefined
        : Number(row["candidate_score"]),
    ...(typeof row["base_output"] === "string"
      ? { baseOutput: row["base_output"] }
      : {}),
    ...(typeof row["candidate_output"] === "string"
      ? { candidateOutput: row["candidate_output"] }
      : {}),
  }));
}

function comparisonOf(value: unknown): EvalComparison {
  const row = recordOf(value, "compare_eval_runs");

  return {
    base: summaryOf(row["base"]) ?? EMPTY_SUMMARY,
    candidate: summaryOf(row["candidate"]) ?? EMPTY_SUMMARY,
    passRateDelta: Number(row["pass_rate_delta"] ?? 0),
    regressions: comparisonItemsOf(row["regressions"], "compare_eval_runs"),
    improvements: comparisonItemsOf(row["improvements"], "compare_eval_runs"),
    unchanged: Number(row["unchanged"] ?? 0),
    missing: Number(row["missing"] ?? 0),
  };
}

const describe = (scorer: EvalScorer | ScorerDescription): ScorerDescription =>
  "score" in scorer ? describeScorer(scorer) : scorer;

/**
 * Evaluation datasets and runs in Postgres, read and written as the service
 * role. Scoring happens in your code (see the scorers and `createEvalJob`); the
 * database keeps the items, the results and the comparison.
 */
export function createAiEvals(options: AiEvalsOptions): AiEvals {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: AiEvals = {
    datasets: {
      create: (name, createOptions = {}) =>
        call(
          "create_eval_dataset",
          {
            name,
            tenant: createOptions.organizationId,
            description: createOptions.description,
          },
          datasetOf,
        ),
    },
    items: {
      add: (datasetId, items) =>
        call(
          "add_eval_items",
          {
            dataset: datasetId,
            items: items.map((item) => ({
              input: item.input,
              expected: item.expected,
              metadata: item.metadata ?? {},
            })),
          },
          Number,
        ),
      addFromFeedback: (datasetId, feedbackOptions = {}) =>
        call(
          "add_eval_items_from_feedback",
          {
            dataset: datasetId,
            rating: feedbackOptions.rating ?? -1,
            since: feedbackOptions.since?.toString(),
            max_rows: feedbackOptions.limit,
          },
          Number,
        ),
      list: (datasetId, listOptions = {}) =>
        call(
          "list_eval_items",
          {
            dataset: datasetId,
            pending_run: listOptions.pendingRun,
            after: listOptions.after,
            max_rows: listOptions.limit,
          },
          (value) => recordsOf(value, "list_eval_items").map(itemOf),
        ),
    },
    runs: {
      create: (datasetId, runOptions) =>
        call(
          "create_eval_run",
          {
            dataset: datasetId,
            prompt_name: runOptions.promptName,
            prompt_version: runOptions.promptVersion,
            model: runOptions.model,
            scorers: (runOptions.scorers ?? []).map(describe),
          },
          runOf,
        ),
      get: (runId) =>
        call("get_eval_run", { run: runId }, (value) =>
          value === null || value === undefined ? undefined : runOf(value),
        ),
      list: (datasetId, listOptions = {}) =>
        call(
          "list_eval_runs",
          { dataset: datasetId, max_rows: listOptions.limit },
          (value) => recordsOf(value, "list_eval_runs").map(runOf),
        ),
      record: (runId, itemId, result) =>
        call(
          "record_eval_result",
          {
            run: runId,
            item: itemId,
            output: result.output,
            scores: result.scores ?? {},
            error: result.error,
            latency_ms: result.latencyMs,
          },
          resultOf,
        ),
      results: (runId, resultOptions = {}) =>
        call(
          "list_eval_results",
          {
            run: runId,
            only_failed: resultOptions.onlyFailed ?? false,
            after: resultOptions.after,
            max_rows: resultOptions.limit,
          },
          (value) => recordsOf(value, "list_eval_results").map(resultOf),
        ),
      finish: (runId, status = "completed") =>
        call("finish_eval_run", { run: runId, status }, runOf),
      compare: (baseRunId, candidateRunId, compareOptions = {}) =>
        call(
          "compare_eval_runs",
          {
            base: baseRunId,
            candidate: candidateRunId,
            score_drop: compareOptions.scoreDrop,
          },
          comparisonOf,
        ),
    },
    exportPromptfoo: (datasetId, exportOptions) =>
      AsyncResult.from(async () => {
        const all: EvalItem[] = [];
        let after: string | undefined;

        for (;;) {
          const page = await client.items.list(datasetId, {
            limit: EXPORT_PAGE,
            ...(after ? { after } : {}),
          });

          if (!page.ok) {
            return page;
          }

          all.push(...page.data);
          const last = page.data.at(-1);

          if (page.data.length < EXPORT_PAGE || last === undefined) {
            break;
          }

          after = last.id;
        }

        return ok(
          toPromptfooConfig(all, {
            description: exportOptions.description ?? `Dataset ${datasetId}`,
            prompt: exportOptions.prompt,
            model: exportOptions.model,
            scorers: exportOptions.scorers.map(describe),
          }),
        );
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "ai-evals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
