import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface ObservationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the observation's extra columns
   * (`blocks.observations.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Observations<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** What a definition's values are. */
export type ObservationValueType =
  | "number"
  | "integer"
  | "boolean"
  | "code"
  | "text"
  | "components";

/** Where a value falls against the definition's ranges. */
export type ObservationFlag =
  | "normal"
  | "low"
  | "high"
  | "critical_low"
  | "critical_high";

/**
 * `final`: the current value. `amended`: replaced by a correction.
 * `entered_in_error`: withdrawn.
 */
export type ObservationStatus = "final" | "amended" | "entered_in_error";

/** How an observation was recorded. */
export type ObservationSource = "manual" | "form" | "device" | "import";

/** The width of a `buckets` bucket, in UTC. */
export type ObservationBucket = "hour" | "day" | "week" | "month";

/** The ranges a numeric value is checked and flagged against. */
export interface ObservationRanges {
  /** Values outside the valid range are rejected. */
  readonly validLow?: number;
  readonly validHigh?: number;
  /** Values outside the reference range are flagged low or high. */
  readonly referenceLow?: number;
  readonly referenceHigh?: number;
  /** Values at or past a critical bound are flagged critical and alerted. */
  readonly criticalLow?: number;
  readonly criticalHigh?: number;
}

/** One part of a `components` definition, such as systolic pressure. */
export interface ObservationComponent extends ObservationRanges {
  readonly key: string;
  readonly title?: string;
  readonly code?: string;
  readonly unit?: string;
  readonly decimals?: number;
  /** Default `false`: a value needs every component that isn't optional. */
  readonly optional?: boolean;
}

/** What an observation measures. */
export interface ObservationDefinition extends ObservationRanges {
  readonly id: string;
  /** Missing for a system definition every organization reads. */
  readonly organizationId?: string;
  readonly system: boolean;
  readonly key: string;
  readonly title: string;
  readonly valueType: ObservationValueType;
  /** A UCUM unit, such as `mm[Hg]`. */
  readonly unit?: string;
  /** The code system URI, such as `http://loinc.org`. */
  readonly codeSystem?: string;
  readonly code?: string;
  readonly components: readonly ObservationComponent[];
  /** The decimals a number is rounded to. */
  readonly decimals?: number;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

export interface ObservationDefinitionInput extends ObservationRanges {
  readonly title: string;
  readonly valueType: ObservationValueType;
  readonly unit?: string;
  readonly codeSystem?: string;
  readonly code?: string;
  /** Required for `components`, one to twenty. */
  readonly components?: readonly ObservationComponent[];
  readonly decimals?: number;
}

/**
 * A value: a number for `number` and `integer`, a boolean, a string for `code`
 * and `text`, or the component values by key.
 */
export type ObservationValue =
  | number
  | boolean
  | string
  | Readonly<Record<string, number>>;

/** One measurement of a record. `F` types the extra columns. */
export interface Observation<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly definitionId: string;
  readonly definitionKey: string;
  readonly title: string;
  readonly valueType: ObservationValueType;
  readonly unit?: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly observedAt: Temporal.Instant;
  readonly value: ObservationValue | null;
  /** Missing when the definition has no ranges. */
  readonly flag?: ObservationFlag;
  readonly status: ObservationStatus;
  /** The observation this one amended. */
  readonly replacesId?: string;
  /** Why it was amended or marked in error. */
  readonly reason?: string;
  readonly method?: string;
  readonly device?: string;
  readonly source: ObservationSource;
  readonly externalId?: string;
  /** The form submission (forms block) it came from. */
  readonly submissionId?: string;
  readonly performerId?: string;
  readonly note?: string;
  readonly createdAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ObservationInput<F extends object = Record<never, never>> {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly definitionKey: string;
  readonly value: ObservationValue;
  /** Default: now. Not in the future. */
  readonly observedAt?: Temporal.Instant;
  readonly method?: string;
  readonly device?: string;
  readonly note?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface ObservationIngestItem<
  F extends object = Record<never, never>,
> extends ObservationInput<F> {
  /** The source's own id: an item seen before is skipped. */
  readonly externalId: string;
  /** Default `device`. */
  readonly source?: "device" | "import";
}

export interface ObservationIngestResult {
  readonly inserted: number;
  readonly skipped: number;
  /** The ids of the inserted observations. */
  readonly ids: readonly string[];
}

/** What an amendment changes; what it leaves out stays. */
export interface ObservationChanges<F extends object = Record<never, never>> {
  readonly value?: ObservationValue;
  readonly observedAt?: Temporal.Instant;
  readonly method?: string;
  readonly device?: string;
  readonly note?: string;
  readonly fields?: Partial<F>;
}

export interface ObservationListOptions {
  readonly definitionKey?: string;
  /** Also the amended and entered-in-error observations. Default `false`. */
  readonly includeAll?: boolean;
  /** Default 100, at most 1000. */
  readonly limit?: number;
}

export interface ObservationRangeOptions {
  readonly since?: Temporal.Instant;
  /** Excluded. */
  readonly until?: Temporal.Instant;
}

/** One point of a series. */
export interface ObservationPoint {
  readonly id: string;
  readonly observedAt: Temporal.Instant;
  readonly value: ObservationValue | null;
  readonly flag?: ObservationFlag;
}

export interface ObservationStats {
  readonly min?: number;
  readonly max?: number;
  readonly avg?: number;
}

/** One bucket of a series: the count and, for numbers, min, max and avg. */
export interface ObservationBucketStats extends ObservationStats {
  readonly bucket: Temporal.Instant;
  readonly count: number;
  /** Per component, for a `components` definition. */
  readonly components: Readonly<Record<string, ObservationStats>>;
}

export interface Observations<F extends object = Record<never, never>> {
  /**
   * Needs `observations.manage`. Saving a key again updates that definition and
   * restores it if archived. A key a system definition uses overrides it for
   * the organization.
   */
  saveDefinition(input: {
    organizationId: string;
    key: string;
    input: ObservationDefinitionInput;
  }): AsyncResult<ObservationDefinition>;
  /** Needs `observations.manage`. Its observations stay. */
  archiveDefinition(definitionId: string): AsyncResult<ObservationDefinition>;
  /** The organization's definitions and the system ones, by title. */
  definitions(
    input: { organizationId: string } & { readonly includeArchived?: boolean },
  ): AsyncResult<readonly ObservationDefinition[]>;
  /** Needs `observations.record` and access to the record. */
  record(input: {
    organizationId: string;
    input: ObservationInput<F>;
  }): AsyncResult<Observation<F>>;
  /** Up to 500 observations, all or none. */
  recordMany(input: {
    organizationId: string;
    inputs: readonly ObservationInput<F>[];
  }): AsyncResult<readonly Observation<F>[]>;
  /**
   * Service role only. Records device or import readings, skipping the ones
   * whose `externalId` was ingested before.
   */
  ingest(input: {
    organizationId: string;
    items: readonly ObservationIngestItem<F>[];
  }): AsyncResult<ObservationIngestResult>;
  /**
   * Needs `observations.record`. Records the corrected observation and marks
   * this one `amended`.
   */
  amend(input: {
    observationId: string;
    changes: ObservationChanges<F>;
    reason: string;
  }): AsyncResult<Observation<F>>;
  /** Needs `observations.record`. Marking twice keeps the first reason. */
  markError(input: {
    observationId: string;
    reason: string;
  }): AsyncResult<Observation<F>>;
  /** A record's observations, the latest first. */
  list(
    input: { subjectType: string; subjectId: string } & ObservationListOptions,
  ): AsyncResult<readonly Observation<F>[]>;
  /** The final values of one definition for a record, oldest first. */
  series(
    input: {
      subjectType: string;
      subjectId: string;
      definitionKey: string;
    } & ObservationRangeOptions,
  ): AsyncResult<readonly ObservationPoint[]>;
  /** The same values counted and summarized per UTC hour, day, week or month. */
  buckets(
    input: {
      subjectType: string;
      subjectId: string;
      definitionKey: string;
      bucket: ObservationBucket;
    } & ObservationRangeOptions,
  ): AsyncResult<readonly ObservationBucketStats[]>;
  /** A record's latest final observation per definition key. */
  latest(input: {
    subjectType: string;
    subjectId: string;
  }): AsyncResult<Readonly<Record<string, Observation<F>>>>;
  /**
   * Needs the forms block. Records the observations a submitted form maps to
   * through `meta.observation`; a submission is recorded only once.
   */
  fromSubmission(submissionId: string): AsyncResult<readonly Observation<F>[]>;
}

const VALUE_TYPES: readonly ObservationValueType[] = [
  "number",
  "integer",
  "boolean",
  "code",
  "text",
  "components",
];

const FLAGS: readonly ObservationFlag[] = [
  "normal",
  "low",
  "high",
  "critical_low",
  "critical_high",
];

const STATUSES: readonly ObservationStatus[] = [
  "final",
  "amended",
  "entered_in_error",
];

const SOURCES: readonly ObservationSource[] = [
  "manual",
  "form",
  "device",
  "import",
];

const RANGE_KEYS = [
  "validLow",
  "validHigh",
  "referenceLow",
  "referenceHigh",
  "criticalLow",
  "criticalHigh",
] as const;

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

const instantOf = (value: unknown): Temporal.Instant =>
  temporal().Instant.from(textOf(value));

const optionalFlag = (value: unknown): ObservationFlag | undefined =>
  value === null || value === undefined
    ? undefined
    : enumOrThrow(value, FLAGS, "observation flag");

function rangesOf(row: Readonly<Record<string, unknown>>): ObservationRanges {
  return Object.fromEntries(
    RANGE_KEYS.flatMap((key) => {
      const value = optionalNumber(row[key]);

      return value === undefined ? [] : [[key, value]];
    }),
  );
}

function valueOf(value: unknown): ObservationValue | null {
  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "string"
  ) {
    return value;
  }

  if (isRecord(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, part]) => [key, numberOf(part)]),
    );
  }

  return null;
}

function componentOf(value: unknown): ObservationComponent {
  const row = recordOf(value, "observation component");

  return {
    key: textOf(row["key"]),
    ...optional("title", optionalText(row["title"])),
    ...optional("code", optionalText(row["code"])),
    ...optional("unit", optionalText(row["unit"])),
    ...optional("decimals", optionalNumber(row["decimals"])),
    ...optional(
      "optional",
      typeof row["optional"] === "boolean" ? row["optional"] : undefined,
    ),
    ...rangesOf(row),
  };
}

function definitionOf(value: unknown, fn: string): ObservationDefinition {
  const row = recordOf(value, fn);
  const components = Array.isArray(row["components"]) ? row["components"] : [];

  return {
    id: textOf(row["id"]),
    system: row["system"] === true,
    key: textOf(row["key"]),
    title: textOf(row["title"]),
    valueType: enumOrThrow(row["valueType"], VALUE_TYPES, "value type"),
    components: components.map(componentOf),
    ...optional("organizationId", optionalText(row["organizationId"])),
    ...optional("unit", optionalText(row["unit"])),
    ...optional("codeSystem", optionalText(row["codeSystem"])),
    ...optional("code", optionalText(row["code"])),
    ...optional("decimals", optionalNumber(row["decimals"])),
    ...rangesOf(row),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
  };
}

function observationOf(value: unknown, fn: string): Observation {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    definitionId: textOf(row["definitionId"]),
    definitionKey: textOf(row["definitionKey"]),
    title: textOf(row["title"]),
    valueType: enumOrThrow(row["valueType"], VALUE_TYPES, "value type"),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    observedAt: instantOf(row["observedAt"]),
    value: valueOf(row["value"]),
    status: enumOrThrow(row["status"], STATUSES, "observation status"),
    source: enumOrThrow(row["source"], SOURCES, "observation source"),
    createdAt: instantOf(row["createdAt"]),
    ...optional("unit", optionalText(row["unit"])),
    ...optional("flag", optionalFlag(row["flag"])),
    ...optional("replacesId", optionalText(row["replacesId"])),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("method", optionalText(row["method"])),
    ...optional("device", optionalText(row["device"])),
    ...optional("externalId", optionalText(row["externalId"])),
    ...optional("submissionId", optionalText(row["submissionId"])),
    ...optional("performerId", optionalText(row["performerId"])),
    ...optional("note", optionalText(row["note"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function pointOf(value: unknown): ObservationPoint {
  const row = recordOf(value, "observation_series");

  return {
    id: textOf(row["id"]),
    observedAt: instantOf(row["observedAt"]),
    value: valueOf(row["value"]),
    ...optional("flag", optionalFlag(row["flag"])),
  };
}

function statsOf(row: Readonly<Record<string, unknown>>): ObservationStats {
  return {
    ...optional("min", optionalNumber(row["min"])),
    ...optional("max", optionalNumber(row["max"])),
    ...optional("avg", optionalNumber(row["avg"])),
  };
}

function bucketOf(value: unknown): ObservationBucketStats {
  const row = recordOf(value, "observation_series");
  const parts = isRecord(row["components"]) ? row["components"] : {};

  return {
    bucket: instantOf(row["bucket"]),
    count: numberOf(row["count"]),
    ...statsOf(row),
    components: Object.fromEntries(
      Object.entries(parts).map(([key, part]) => [
        key,
        statsOf(recordOf(part, "observation_series")),
      ]),
    ),
  };
}

function ingestOf(value: unknown): ObservationIngestResult {
  const row = recordOf(value, "ingest_observations");

  return {
    inserted: numberOf(row["inserted"]),
    skipped: numberOf(row["skipped"]),
    ids: Array.isArray(row["ids"]) ? row["ids"].map(textOf) : [],
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

function definitionArgs(
  input: ObservationDefinitionInput,
): Record<string, unknown> {
  return {
    title: input.title,
    valueType: input.valueType,
    ...optional("unit", input.unit),
    ...optional("codeSystem", input.codeSystem),
    ...optional("code", input.code),
    ...optional("components", input.components),
    ...optional("decimals", input.decimals),
    ...Object.fromEntries(
      RANGE_KEYS.flatMap((key) =>
        input[key] === undefined ? [] : [[key, input[key]]],
      ),
    ),
  };
}

const details = (input: {
  readonly method?: string;
  readonly device?: string;
  readonly note?: string;
}): Record<string, string> => ({
  ...optional("method", input.method),
  ...optional("device", input.device),
  ...optional("note", input.note),
});

/** The `observations` SQL module as typed calls. */
export function createObservations<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ObservationsOptions<S>): Observations<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "observation fields",
  );

  const one = (fn: string) => (value: unknown) => observationOf(value, fn);

  const item = (
    input: ObservationInput<F> | ObservationIngestItem<F>,
    checked: Readonly<Record<string, unknown>> | undefined,
  ): Record<string, unknown> => ({
    subjectType: input.subjectType,
    subjectId: input.subjectId,
    definitionKey: input.definitionKey,
    value: input.value,
    ...optional("observedAt", input.observedAt?.toString()),
    details: details(input),
    ...("externalId" in input ? { externalId: input.externalId } : {}),
    ...("source" in input ? optional("source", input.source) : {}),
    ...(checked === undefined ? {} : { fields: checked }),
  });

  const items = (
    inputs: readonly (ObservationInput<F> | ObservationIngestItem<F>)[],
  ): AsyncResult<readonly Record<string, unknown>[]> =>
    inputs.reduce<AsyncResult<readonly Record<string, unknown>[]>>(
      (all, input) =>
        all.andThen((done) =>
          fields
            .args(input.fields)
            .map((checked) => [...done, item(input, checked)]),
        ),
      AsyncResult.ok([]),
    );

  const client: Observations<F> = {
    saveDefinition: ({ organizationId, key, input }) =>
      call(
        "save_observation_definition",
        { tenant: organizationId, key, definition: definitionArgs(input) },
        (value) => definitionOf(value, "save_observation_definition"),
      ),
    archiveDefinition: (definitionId) =>
      call(
        "archive_observation_definition",
        { definition_id: definitionId },
        (value) => definitionOf(value, "archive_observation_definition"),
      ),
    definitions: ({ organizationId, ...list }) =>
      call(
        "list_observation_definitions",
        {
          tenant: organizationId,
          include_archived: list.includeArchived ?? false,
        },
        many("list_observation_definitions", definitionOf),
      ),
    // One item of `record_observations`: a jsonb array goes as JSON over
    // every transport, where a lone text value for a jsonb argument doesn't.
    record: ({ organizationId, input }) =>
      items([input]).andThen((checked) =>
        call(
          "record_observations",
          { tenant: organizationId, items: checked },
          (value) => {
            const [row] = recordsOf(value, "record_observations");

            return observationOf(row, "record_observations");
          },
        ).andThen(fields.row),
      ),
    recordMany: ({ organizationId, inputs }) =>
      items(inputs).andThen((checked) =>
        call(
          "record_observations",
          { tenant: organizationId, items: checked },
          many("record_observations", observationOf),
        ).andThen(fields.rows),
      ),
    ingest: ({ organizationId, items: list }) =>
      items(list).andThen((checked) =>
        call(
          "ingest_observations",
          { tenant: organizationId, items: checked },
          ingestOf,
        ),
      ),
    amend: ({ observationId, changes, reason }) =>
      fields
        .args(changes.fields)
        .andThen((checked) =>
          call(
            "amend_observation",
            {
              observation_id: observationId,
              changes: {
                ...optional("value", changes.value),
                ...optional("observedAt", changes.observedAt?.toString()),
                details: details(changes),
                ...(checked === undefined ? {} : { fields: checked }),
              },
              reason,
            },
            one("amend_observation"),
          ).andThen(fields.row),
        ),
    markError: ({ observationId, reason }) =>
      call(
        "mark_observation_error",
        { observation_id: observationId, reason },
        one("mark_observation_error"),
      ).andThen(fields.row),
    list: ({ subjectType, subjectId, ...list }) =>
      call(
        "list_observations",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          definition_key: list.definitionKey ?? null,
          include_all: list.includeAll ?? false,
          max_rows: list.limit ?? 100,
        },
        many("list_observations", observationOf),
      ).andThen(fields.rows),
    series: ({ subjectType, subjectId, definitionKey, ...range }) =>
      call(
        "observation_series",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          definition_key: definitionKey,
          since: range.since?.toString() ?? null,
          until: range.until?.toString() ?? null,
          bucket: null,
        },
        (value) => recordsOf(value, "observation_series").map(pointOf),
      ),
    buckets: ({ subjectType, subjectId, definitionKey, bucket, ...range }) =>
      call(
        "observation_series",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          definition_key: definitionKey,
          since: range.since?.toString() ?? null,
          until: range.until?.toString() ?? null,
          bucket,
        },
        (value) => recordsOf(value, "observation_series").map(bucketOf),
      ),
    latest: ({ subjectType, subjectId }) =>
      call(
        "latest_observations",
        { subject_type: subjectType, subject_id: subjectId },
        (value) =>
          Object.entries(recordOf(value, "latest_observations")).map(
            ([key, row]) =>
              [key, observationOf(row, "latest_observations")] as const,
          ),
      ).andThen((pairs) =>
        fields
          .rows(pairs.map(([, row]) => row))
          .map((rows): Readonly<Record<string, Observation<F>>> =>
            Object.fromEntries(
              rows.map((row, index) => [pairs[index]?.[0] ?? "", row]),
            ),
          ),
      ),
    fromSubmission: (submissionId) =>
      call(
        "observations_from_submission",
        { submission_id: submissionId },
        many("observations_from_submission", observationOf),
      ).andThen(fields.rows),
  };

  return withBlockHooks(client, options.hooks, {
    block: "observations",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
