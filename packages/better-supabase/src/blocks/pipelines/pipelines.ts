import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
  readAllFields,
  readFields,
  type RowFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  instantArg,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** The fixed outcome every stage category maps to. */
export type PipelineOutcome = "open" | "success" | "failure";

const OUTCOMES: readonly PipelineOutcome[] = ["open", "success", "failure"];

export interface PipelineStage {
  readonly id: string;
  readonly pipelineId: string;
  readonly key: string;
  /** The key the stage was seeded with, which renames keep. */
  readonly systemKey?: string;
  readonly name: string;
  readonly color?: string;
  readonly rank: string;
  /** A category the subject type declares, such as `won` or `started`. */
  readonly category: string;
  readonly outcome: PipelineOutcome;
  /** Win probability 0 to 100, the default for records in the stage. */
  readonly probability?: number;
  readonly rottingAfterDays?: number;
  readonly wipLimit?: number;
}

export interface Pipeline<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  /** The scope the pipeline belongs to, such as one job's id. */
  readonly scopeId?: string;
  readonly key: string;
  readonly name: string;
  readonly rank: string;
  readonly isDefault: boolean;
  /** Its active stages in board order. Empty on the result of `save`. */
  readonly stages: readonly PipelineStage[];
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface PipelineInput<F extends object = Record<never, never>> {
  /** Leave out to create a pipeline. */
  readonly id?: string;
  readonly subjectType: string;
  readonly key: string;
  readonly name: string;
  readonly scopeId?: string;
  readonly isDefault?: boolean;
  /** Values for the app's extra columns (`options.extraColumns`); left out keeps the stored ones. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface PipelineStageInput {
  /** Leave out to add a stage at the end. */
  readonly id?: string;
  readonly key: string;
  readonly name: string;
  readonly category: string;
  readonly probability?: number;
  readonly rottingAfterDays?: number;
  readonly wipLimit?: number;
  readonly color?: string;
}

/** An allowed stage change. Without any, every change is allowed. */
export interface PipelineTransition {
  readonly from: string;
  readonly to: string;
}

/** One currency's totals in a board column. Amounts are minor units. */
export interface PipelineTotal {
  readonly currency: string;
  readonly amount: bigint;
  /** The amount times each record's probability (or its stage's), rounded. */
  readonly weighted: bigint;
}

/** One board column: a stage with the records the caller can see in it. */
export interface PipelineColumn {
  readonly stageId: string;
  readonly key: string;
  readonly name: string;
  readonly color?: string;
  readonly category: string;
  readonly outcome: PipelineOutcome;
  readonly probability?: number;
  readonly wipLimit?: number;
  readonly count: number;
  /** Whether the column holds more records than its WIP limit. */
  readonly overLimit: boolean;
  readonly totals: readonly PipelineTotal[];
}

export interface PipelineStats {
  readonly won: number;
  readonly lost: number;
  /** Won over won plus lost, or `undefined` when nothing closed. */
  readonly winRate?: number;
  readonly stages: readonly {
    readonly stageId: string;
    readonly key: string;
    readonly entered: number;
    /** How long records that left the stage stayed, on average. */
    readonly averageSeconds?: number;
  }[];
}

/** An open record and how long it has been in its stage. */
export interface PipelineHealth {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly stageId: string;
  readonly enteredAt: Temporal.Instant;
  readonly daysInStage: number;
  /** Whether it sits longer than the stage's rotting limit. */
  readonly rotting: boolean;
}

export interface Pipelines<F extends object = Record<never, never>> {
  /** The organization's active pipelines of a subject type, with their stages. */
  list(organizationId: string, subjectType: string): AsyncResult<Pipeline<F>[]>;
  /** Creates or renames a pipeline. The first of a type and scope is its default. */
  save(
    organizationId: string,
    input: PipelineInput<F>,
  ): AsyncResult<Pipeline<F>>;
  /** Archives a pipeline that holds no records. */
  archive(pipelineId: string): AsyncResult<boolean>;
  /** Adds a stage at the end of a pipeline, or changes one. */
  saveStage(
    pipelineId: string,
    input: PipelineStageInput,
  ): AsyncResult<PipelineStage>;
  /** Moves a stage between the stages with rank keys `previous` and `next`. */
  reorderStage(stageId: string, neighbors: RankNeighbors): AsyncResult<string>;
  /** Archives an empty stage. A pipeline keeps at least one open stage. */
  archiveStage(stageId: string): AsyncResult<boolean>;
  /** Replaces the allowed stage changes. An empty list allows every change. */
  setTransitions(
    pipelineId: string,
    transitions: readonly PipelineTransition[],
  ): AsyncResult<number>;
  /** The board: each active stage with its count and totals per currency. */
  board(
    subjectType: string,
    pipelineId: string,
    options?: { readonly owner?: string },
  ): AsyncResult<PipelineColumn[]>;
  /** Entries, time in stage and win rate from the stage history. */
  stats(
    pipelineId: string,
    window: {
      readonly since: Temporal.Instant;
      readonly until: Temporal.Instant;
    },
  ): AsyncResult<PipelineStats>;
  /** The open records, oldest entry first, with their days in stage. */
  health(pipelineId: string): AsyncResult<PipelineHealth[]>;
}

export interface PipelinesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. */
  readonly schema?: string;
  /**
   * A Standard Schema for the extra columns of the pipelines table
   * (`blocks.pipelines.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Pipelines<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const bigintOf = (value: unknown): bigint =>
  typeof value === "string" || typeof value === "number" ? BigInt(value) : 0n;

function stageOf(value: unknown): PipelineStage {
  const row = recordOf(value, "pipeline stage");
  const systemKey = optionalText(row["system_key"]);
  const color = optionalText(row["color"]);
  const probability = numberOf(row["probability"]);
  const rotting = numberOf(row["rotting_after_days"]);
  const wipLimit = numberOf(row["wip_limit"]);

  return {
    id: textOf(row["id"]),
    pipelineId: textOf(row["pipeline_id"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    rank: textOf(row["rank"]),
    category: textOf(row["category"]),
    outcome: enumOrThrow(row["outcome"], OUTCOMES, "pipeline stage outcome"),
    ...(systemKey === undefined ? {} : { systemKey }),
    ...(color === undefined ? {} : { color }),
    ...(probability === undefined ? {} : { probability }),
    ...(rotting === undefined ? {} : { rottingAfterDays: rotting }),
    ...(wipLimit === undefined ? {} : { wipLimit }),
  };
}

function pipelineOf(value: unknown): Pipeline {
  const row = recordOf(value, "pipeline");
  const scopeId = optionalText(row["scope_id"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    subjectType: textOf(row["subject_type"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    rank: textOf(row["rank"]),
    isDefault: row["is_default"] === true,
    stages: recordsOf(row["stages"], "pipeline stages").map(stageOf),
    fields: rowFields(row["fields"]),
    ...(scopeId === undefined ? {} : { scopeId }),
  };
}

function columnOf(value: unknown): PipelineColumn {
  const row = recordOf(value, "pipeline_board");
  const color = optionalText(row["color"]);
  const probability = numberOf(row["probability"]);
  const wipLimit = numberOf(row["wipLimit"]);

  return {
    stageId: textOf(row["stageId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    category: textOf(row["category"]),
    outcome: enumOrThrow(row["outcome"], OUTCOMES, "pipeline stage outcome"),
    count: numberOf(row["count"]) ?? 0,
    overLimit: row["overLimit"] === true,
    totals: recordsOf(row["totals"], "pipeline_board totals").map((total) => ({
      currency: textOf(total["currency"]),
      amount: bigintOf(total["amount"]),
      weighted: bigintOf(total["weighted"]),
    })),
    ...(color === undefined ? {} : { color }),
    ...(probability === undefined ? {} : { probability }),
    ...(wipLimit === undefined ? {} : { wipLimit }),
  };
}

function statsOf(value: unknown): PipelineStats {
  const row = recordOf(value, "pipeline_stats");
  const winRate = numberOf(row["winRate"]);

  return {
    won: numberOf(row["won"]) ?? 0,
    lost: numberOf(row["lost"]) ?? 0,
    ...(winRate === undefined ? {} : { winRate }),
    stages: recordsOf(row["stages"], "pipeline_stats stages").map((stage) => {
      const averageSeconds = numberOf(stage["averageSeconds"]);

      return {
        stageId: textOf(stage["stageId"]),
        key: textOf(stage["key"]),
        entered: numberOf(stage["entered"]) ?? 0,
        ...(averageSeconds === undefined ? {} : { averageSeconds }),
      };
    }),
  };
}

function healthOf(value: unknown): PipelineHealth {
  const row = recordOf(value, "pipeline_health");

  return {
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    stageId: textOf(row["stageId"]),
    enteredAt: requiredInstant(row["enteredAt"], "enteredAt"),
    daysInStage: numberOf(row["daysInStage"]) ?? 0,
    rotting: row["rotting"] === true,
  };
}

/**
 * The pipelines block: tenant-editable pipelines and stages for the subject
 * types `blocks.pipelines.options.subjects` binds, and the board,
 * stats and health reads over them. Moving a record is a plain update of
 * its stage column, or `rank.move` with the stage id as the group.
 */
export function createPipelines<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: PipelinesOptions<S>): Pipelines<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "pipeline fields");

  const client: Pipelines<F> = {
    list: (organizationId, subjectType) =>
      call(
        "list_pipelines",
        { tenant: organizationId, subject_type: subjectType },
        (value) => recordsOf(value, "list_pipelines").map(pipelineOf),
      ).andThen((pipelines) => readAllFields(fields, pipelines)),
    save: (organizationId, input) =>
      writeFields(fields, input.fields, (checked) =>
        call(
          "save_pipeline",
          {
            tenant: organizationId,
            pipeline: input.id ?? null,
            subject_type: input.subjectType,
            key: input.key,
            name: input.name,
            scope_id: input.scopeId ?? null,
            is_default: input.isDefault ?? null,
            fields: checked,
          },
          pipelineOf,
        ),
      ).andThen((pipeline) => readFields(fields, pipeline)),
    archive: (pipelineId) =>
      call(
        "archive_pipeline",
        { pipeline: pipelineId },
        (value) => value === true,
      ),
    saveStage: (pipelineId, input) =>
      call(
        "save_pipeline_stage",
        {
          pipeline: pipelineId,
          stage: input.id ?? null,
          key: input.key,
          name: input.name,
          category: input.category,
          probability: input.probability ?? null,
          rotting_after_days: input.rottingAfterDays ?? null,
          wip_limit: input.wipLimit ?? null,
          color: input.color ?? null,
        },
        stageOf,
      ),
    reorderStage: (stageId, neighbors) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call(
        "rank_pipeline_stage",
        { stage: stageId, rank: key.data },
        () => key.data,
      );
    },
    archiveStage: (stageId) =>
      call(
        "archive_pipeline_stage",
        { stage: stageId },
        (value) => value === true,
      ),
    setTransitions: (pipelineId, transitions) =>
      call(
        "set_pipeline_transitions",
        {
          pipeline: pipelineId,
          pairs: transitions.map((item) => ({ from: item.from, to: item.to })),
        },
        (value) => numberOf(value) ?? 0,
      ),
    board: (subjectType, pipelineId, board = {}) =>
      call(
        "pipeline_board",
        {
          subject_type: subjectType,
          pipeline: pipelineId,
          owner: board.owner ?? null,
        },
        (value) => recordsOf(value, "pipeline_board").map(columnOf),
      ),
    stats: (pipelineId, window) =>
      call(
        "pipeline_stats",
        {
          pipeline: pipelineId,
          since: instantArg(window.since),
          until: instantArg(window.until),
        },
        statsOf,
      ),
    health: (pipelineId) =>
      call("pipeline_health", { pipeline: pipelineId }, (value) =>
        recordsOf(value, "pipeline_health").map(healthOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "pipelines",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
