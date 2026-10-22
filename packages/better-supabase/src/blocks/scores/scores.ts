import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  notFoundError,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ScoresOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Scores>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** Points a subject earns when its fields match a filter tree. */
export interface ScoreRule {
  readonly id: string;
  readonly label?: string;
  /** A filter tree over the rules field catalog of the model's subject type. */
  readonly conditions: FilterQuery;
  /** Negative to subtract. */
  readonly points: number;
}

/**
 * A number times a weight: a number field of the subject (`field`) or the
 * record's vote score from the `reactions` block (`votes`).
 */
export interface ScoreMetric {
  readonly id: string;
  readonly label?: string;
  readonly source: "field" | "votes";
  /** The rules field id, for `source: "field"`. */
  readonly field?: string;
  /** Default 1. */
  readonly weight?: number;
  /** The most points the metric adds or subtracts. */
  readonly cap?: number;
}

/** A named range: the first band whose `min` the score reaches. */
export interface ScoreBand {
  readonly label: string;
  readonly min: number;
}

/** A scoring configuration, such as lead scoring or account health. */
export interface ScoreModel {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly subjectType: string;
  readonly rules: readonly ScoreRule[];
  readonly metrics: readonly ScoreMetric[];
  /** Highest `min` first. */
  readonly bands: readonly ScoreBand[];
  readonly enabled: boolean;
  /** Goes up when rules, metrics or bands change. */
  readonly version: number;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ScoreModelVersion {
  readonly version: number;
  readonly rules: readonly ScoreRule[];
  readonly metrics: readonly ScoreMetric[];
  readonly bands: readonly ScoreBand[];
  readonly savedBy?: string;
  readonly savedAt: Temporal.Instant;
}

export interface ScoreModelDetail extends ScoreModel {
  /** Newest first. */
  readonly versions: readonly ScoreModelVersion[];
}

/**
 * A new model (`key`, `name` and `subjectType`), or with `id`, the keys to
 * change. `version`, when given, must be the stored one.
 */
export interface ScoreModelInput {
  readonly id?: string;
  readonly version?: number;
  readonly key?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly subjectType?: string;
  readonly rules?: readonly ScoreRule[];
  readonly metrics?: readonly ScoreMetric[];
  readonly bands?: readonly ScoreBand[];
  readonly enabled?: boolean;
}

/** How a score adds up. */
export interface ScoreBreakdown {
  readonly rules: readonly {
    readonly id: string;
    readonly label?: string;
    readonly matched: boolean;
    readonly points: number;
  }[];
  readonly metrics: readonly {
    readonly id: string;
    readonly label?: string;
    /** `null` when the field was empty. */
    readonly value: number | null;
    readonly points: number;
  }[];
}

/** A subject's score under one model, at one model version. */
export interface Score {
  readonly id: string;
  readonly organizationId: string;
  readonly modelId: string;
  readonly modelKey: string;
  /** From `forSubject`. */
  readonly modelName?: string;
  readonly modelVersion: number;
  readonly subject: SubjectRef;
  readonly score: number;
  readonly band?: string;
  readonly breakdown: ScoreBreakdown;
  /** Whether this is the subject's latest score under the model. */
  readonly current: boolean;
  readonly computedAt: Temporal.Instant;
}

export interface ComputedScore extends Score {
  /** Whether this computation saved a new score. */
  readonly changed: boolean;
}

/** The `scores` SQL module as typed calls. */
export interface Scores {
  /** Needs `scores.manage`. Saves a version when rules, metrics or bands change. */
  saveModel(input: ScoreModelInput): AsyncResult<ScoreModel>;
  /** The block tenant's models, by key. */
  models(options?: {
    readonly subjectType?: string;
  }): AsyncResult<readonly ScoreModel[]>;
  /** One model with its versions; `not_found` when the caller can't read it. */
  model(modelId: string): AsyncResult<ScoreModelDetail>;
  /** Needs `scores.manage`. False when there was no such model. */
  deleteModel(modelId: string): AsyncResult<boolean>;
  /**
   * Scores a record with the model `modelKey`. `fields` are the record's values
   * the way the rules block reads them (the same object `run` takes). Needs
   * `scores.compute` or the service role.
   */
  compute(
    modelKey: string,
    subject: SubjectRef,
    fields: Readonly<Record<string, unknown>>,
    options?: { readonly timeZone?: string },
  ): AsyncResult<ComputedScore>;
  /** A record's current scores, one per model. */
  forSubject(subject: SubjectRef): AsyncResult<readonly Score[]>;
  /** A record's scores under one model, newest first. */
  history(
    modelKey: string,
    subject: SubjectRef,
    options?: { readonly pageSize?: number },
  ): AsyncResult<readonly Score[]>;
  /** The highest current scores under one model. */
  top(
    modelKey: string,
    options?: {
      readonly band?: string;
      readonly minScore?: number;
      readonly pageSize?: number;
    },
  ): AsyncResult<readonly Score[]>;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number => Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function isGroup(value: unknown): value is FilterQuery {
  return (
    isRecord(value) &&
    value["type"] === "group" &&
    typeof value["id"] === "string" &&
    (value["combinator"] === "and" || value["combinator"] === "or") &&
    Array.isArray(value["rules"])
  );
}

function conditionsOf(value: unknown): FilterQuery {
  if (!isGroup(value)) {
    throw new TypeError(
      `a score rule's conditions are ${JSON.stringify(value)}`,
    );
  }

  return value;
}

function rulesOf(value: unknown, fn: string): readonly ScoreRule[] {
  return recordsOf(value ?? [], fn).map((rule) => ({
    id: textOf(rule["id"]),
    conditions: conditionsOf(rule["conditions"]),
    points: numberOf(rule["points"]),
    ...optional("label", optionalText(rule["label"])),
  }));
}

function metricsOf(value: unknown, fn: string): readonly ScoreMetric[] {
  return recordsOf(value ?? [], fn).map((metric) => ({
    id: textOf(metric["id"]),
    source: metric["source"] === "votes" ? "votes" : "field",
    ...optional("label", optionalText(metric["label"])),
    ...optional("field", optionalText(metric["field"])),
    ...optional("weight", optionalNumber(metric["weight"])),
    ...optional("cap", optionalNumber(metric["cap"])),
  }));
}

function bandsOf(value: unknown, fn: string): readonly ScoreBand[] {
  return recordsOf(value ?? [], fn).map((band) => ({
    label: textOf(band["label"]),
    min: numberOf(band["min"]),
  }));
}

function modelOf(value: unknown, fn: string): ScoreModel {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    subjectType: textOf(row["subjectType"]),
    rules: rulesOf(row["rules"], fn),
    metrics: metricsOf(row["metrics"], fn),
    bands: bandsOf(row["bands"], fn),
    enabled: row["enabled"] !== false,
    version: numberOf(row["version"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function breakdownOf(value: unknown, fn: string): ScoreBreakdown {
  const row = isRecord(value) ? value : {};

  return {
    rules: recordsOf(row["rules"] ?? [], fn).map((rule) => ({
      id: textOf(rule["id"]),
      matched: rule["matched"] === true,
      points: numberOf(rule["points"]),
      ...optional("label", optionalText(rule["label"])),
    })),
    metrics: recordsOf(row["metrics"] ?? [], fn).map((metric) => ({
      id: textOf(metric["id"]),
      value: optionalNumber(metric["value"]) ?? null,
      points: numberOf(metric["points"]),
      ...optional("label", optionalText(metric["label"])),
    })),
  };
}

function scoreOf(value: unknown, fn: string): Score {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    modelId: textOf(row["modelId"]),
    modelKey: textOf(row["modelKey"]),
    modelVersion: numberOf(row["modelVersion"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    score: numberOf(row["score"]),
    breakdown: breakdownOf(row["breakdown"], fn),
    current: row["current"] === true,
    computedAt: requiredInstant(row["computedAt"], "computedAt"),
    ...optional("modelName", optionalText(row["modelName"])),
    ...optional("band", optionalText(row["band"])),
  };
}

const scoresOf = (value: unknown, fn: string): readonly Score[] =>
  recordsOf(value, fn).map((row) => scoreOf(row, fn));

/** The input keys the SQL function reads; undefined keys stay out. */
function modelArg(input: ScoreModelInput): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  const entries: [string, unknown][] = Object.entries(input);

  for (const [key, value] of entries) {
    if (value !== undefined) {
      out[key] = value;
    }
  }

  return out;
}

/** The `scores` SQL module as typed calls. */
export function createScores(options: ScoresOptions): Scores {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Scores = {
    saveModel: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_score_model",
          { tenant: organizationId, model: modelArg(input) },
          (value) => modelOf(value, "save_score_model"),
        ),
      ),
    models: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_score_models",
          { tenant: organizationId, subject_type: filter.subjectType ?? null },
          (value) =>
            recordsOf(value, "list_score_models").map((row) =>
              modelOf(row, "list_score_models"),
            ),
        ),
      ),
    model: (modelId) =>
      call("get_score_model", { model_id: modelId }, (value) => value).andThen(
        (value) => {
          if (!isRecord(value)) {
            return AsyncResult.err(
              notFoundError(
                "No score model you can see has this id",
                "SCORES_MODEL_NOT_FOUND",
              ),
            );
          }

          const fn = "get_score_model";

          return AsyncResult.ok({
            ...modelOf(value, fn),
            versions: recordsOf(value["versions"] ?? [], fn).map((row) => ({
              version: numberOf(row["version"]),
              rules: rulesOf(row["rules"], fn),
              metrics: metricsOf(row["metrics"], fn),
              bands: bandsOf(row["bands"], fn),
              savedAt: requiredInstant(row["savedAt"], "savedAt"),
              ...optional("savedBy", optionalText(row["savedBy"])),
            })),
          });
        },
      ),
    deleteModel: (modelId) =>
      call(
        "delete_score_model",
        { model_id: modelId },
        (value) => value === true,
      ),
    compute: (modelKey, subject, fields, compute = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "compute_score",
          {
            tenant: organizationId,
            model_key: modelKey,
            subject_type: subject.type,
            subject_id: subject.id,
            subject: fields,
            time_zone: compute.timeZone ?? "UTC",
          },
          (value) => ({
            ...scoreOf(value, "compute_score"),
            changed: recordOf(value, "compute_score")["changed"] === true,
          }),
        ),
      ),
    forSubject: (subject) =>
      tenant().andThen((organizationId) =>
        call(
          "subject_scores",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) => scoresOf(value, "subject_scores"),
        ),
      ),
    history: (modelKey, subject, filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "score_history",
          {
            tenant: organizationId,
            model_key: modelKey,
            subject_type: subject.type,
            subject_id: subject.id,
            page_size: filter.pageSize ?? null,
          },
          (value) => scoresOf(value, "score_history"),
        ),
      ),
    top: (modelKey, filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "top_scores",
          {
            tenant: organizationId,
            model_key: modelKey,
            band: filter.band ?? null,
            min_score: filter.minScore ?? null,
            page_size: filter.pageSize ?? null,
          },
          (value) => scoresOf(value, "top_scores"),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "scores",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
