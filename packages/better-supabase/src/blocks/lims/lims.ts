import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  LIMS_RESULT_OUTCOMES,
  LIMS_SAMPLE_STATUSES,
} from "../../sql/modules/lims-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a sample is in the laboratory. */
export type LimsSampleStatus = (typeof LIMS_SAMPLE_STATUSES)[number];

/** Whether a result lies inside the method's specification limits. */
export type LimsResultOutcome = (typeof LIMS_RESULT_OUTCOMES)[number];

/** What a laboratory measures, with its specification limits. */
export interface LimsMethod {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly unit?: string;
  /** A result below this is out of specification. */
  readonly lowerLimit?: number;
  /** A result above this is out of specification. */
  readonly upperLimit?: number;
  /** The form (the forms block) that captures the readings. */
  readonly formId?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface LimsMethodInput {
  /** Lowercase letters, digits and underscores. Cannot change once saved. */
  readonly key: string;
  readonly name: string;
  readonly unit?: string | null;
  readonly lowerLimit?: number | null;
  /** At or above `lowerLimit`. */
  readonly upperLimit?: number | null;
  readonly formId?: string | null;
}

/** One measurement of a method on a sample. */
export interface LimsResult {
  readonly id: string;
  readonly organizationId: string;
  readonly sampleId: string;
  readonly methodId: string;
  readonly value: number;
  readonly outcome: LimsResultOutcome;
  /** The asset that produced the result. */
  readonly instrumentId?: string;
  /** The form submission with the readings. */
  readonly submissionId?: string;
  /** The nonconformity case an out of specification result opened. */
  readonly caseId?: string;
  readonly note?: string;
  readonly testedBy?: string;
  readonly testedAt: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface LimsResultInput {
  readonly value: number;
  readonly instrumentId?: string;
  readonly submissionId?: string;
  /** Default now. */
  readonly testedAt?: Temporal.Instant;
  readonly note?: string | null;
}

/** A sample received for testing. */
export interface LimsSample {
  readonly id: string;
  readonly organizationId: string;
  /** `SMP-1`, or the numbering block's format. */
  readonly number: string;
  readonly title: string;
  readonly kind?: string;
  readonly lot?: string;
  readonly receivedOn: Temporal.PlainDate;
  readonly status: LimsSampleStatus;
  readonly notes?: string;
  readonly rejectionReason?: string;
  readonly completedAt?: Temporal.Instant;
  readonly releasedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A sample with its results, newest first. */
export interface LimsSampleDetail extends LimsSample {
  readonly results: readonly LimsResult[];
}

export interface LimsSampleInput {
  readonly title: string;
  readonly kind?: string | null;
  readonly lot?: string | null;
  /** Default today. */
  readonly receivedOn?: Temporal.PlainDate;
  readonly notes?: string | null;
}

export interface LimsSampleListOptions {
  readonly status?: LimsSampleStatus;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** The answer of {@link Lims.instrumentStatus}. */
export interface LimsInstrumentStatus {
  readonly instrumentId: string;
  /** Whether `options.instrumentQualification` applies. */
  readonly required: boolean;
  /** Whether the instrument may be used that day. */
  readonly qualified: boolean;
}

export interface Lims {
  /**
   * Creates a method, or updates the one named by `methodId`; needs
   * `lims.manage`.
   */
  saveMethod(
    input: LimsMethodInput,
    methodId?: string,
  ): AsyncResultType<LimsMethod>;
  /** Archives a method. Its results stay; needs `lims.manage`. */
  archiveMethod(methodId: string): AsyncResultType<LimsMethod>;
  listMethods(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResultType<readonly LimsMethod[]>;
  /** Registers and numbers a sample; needs `lims.write`. */
  registerSample(input: LimsSampleInput): AsyncResultType<LimsSample>;
  getSample(sampleId: string): AsyncResultType<LimsSampleDetail>;
  listSamples(
    options?: LimsSampleListOptions,
  ): AsyncResultType<readonly LimsSample[]>;
  /**
   * Records a result and checks it against the method's limits. An out of
   * specification result opens a nonconformity case when the cases block is
   * installed. With `options.instrumentQualification` the instrument must hold
   * that qualification on the test date. Needs `lims.write`.
   */
  recordResult(
    sampleId: string,
    methodId: string,
    input: LimsResultInput,
  ): AsyncResultType<LimsResult>;
  /** Marks testing as done; needs `lims.write`. */
  completeSample(sampleId: string): AsyncResultType<LimsSample>;
  /**
   * Releases a completed sample. Refused while the latest result of a method is
   * out of specification; needs `lims.manage`.
   */
  releaseSample(sampleId: string): AsyncResultType<LimsSample>;
  /** Rejects a sample that is not released; needs `lims.manage`. */
  rejectSample(sampleId: string, reason: string): AsyncResultType<LimsSample>;
  /** Whether an instrument may be used on a day (default today). */
  instrumentStatus(
    assetId: string,
    on?: Temporal.PlainDate,
  ): AsyncResultType<LimsInstrumentStatus>;
}

/** Options for {@link createLims}. */
export interface LimsOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Lims>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const requiredNumber = (value: unknown, name: string): number => {
  if (typeof value !== "number") {
    throw new TypeError(`${name} is not a number`);
  }

  return value;
};

function plainDate(value: unknown, name: string): Temporal.PlainDate {
  if (typeof value !== "string") {
    throw new TypeError(`${name} is missing`);
  }

  return temporal().PlainDate.from(value);
}

function methodOf(value: unknown, fn: string): LimsMethod {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("unit", optionalText(row["unit"])),
    ...optional("lowerLimit", numberOf(row["lowerLimit"])),
    ...optional("upperLimit", numberOf(row["upperLimit"])),
    ...optional("formId", optionalText(row["formId"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function resultOf(value: unknown, fn: string): LimsResult {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    sampleId: textOf(row["sampleId"]),
    methodId: textOf(row["methodId"]),
    value: requiredNumber(row["value"], "value"),
    outcome: enumOrThrow(row["outcome"], LIMS_RESULT_OUTCOMES, "outcome"),
    testedAt: requiredInstant(row["testedAt"], "testedAt"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("instrumentId", optionalText(row["instrumentId"])),
    ...optional("submissionId", optionalText(row["submissionId"])),
    ...optional("caseId", optionalText(row["caseId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("testedBy", optionalText(row["testedBy"])),
  };
}

function sampleOf(value: unknown, fn: string): LimsSample {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    title: textOf(row["title"]),
    receivedOn: plainDate(row["receivedOn"], "receivedOn"),
    status: enumOrThrow(row["status"], LIMS_SAMPLE_STATUSES, "sample status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("kind", optionalText(row["kind"])),
    ...optional("lot", optionalText(row["lot"])),
    ...optional("notes", optionalText(row["notes"])),
    ...optional("rejectionReason", optionalText(row["rejectionReason"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("releasedAt", optionalInstant(row["releasedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

/**
 * A laboratory information system: samples, test methods with specification
 * limits, results and the instruments that produced them. An out of
 * specification result opens a nonconformity case, and instruments can be
 * required to hold a valid qualification.
 */
export function createLims(options: LimsOptions): Lims {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const client: Lims = {
    saveMethod: (input, methodId) =>
      tenant().andThen((organizationId) =>
        call(
          "save_lims_method",
          {
            tenant: organizationId,
            input: definedOf(input),
            ...(methodId === undefined ? {} : { method_id: methodId }),
          },
          (value) => methodOf(value, "save_lims_method"),
        ),
      ),
    archiveMethod: (methodId) =>
      call("archive_lims_method", { method_id: methodId }, (value) =>
        methodOf(value, "archive_lims_method"),
      ),
    listMethods: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_lims_methods",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_lims_methods").map((row) =>
              methodOf(row, "list_lims_methods"),
            ),
        ),
      ),
    registerSample: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "register_sample",
          {
            tenant: organizationId,
            input: definedOf({
              ...input,
              receivedOn: input.receivedOn?.toString(),
            }),
          },
          (value) => sampleOf(value, "register_sample"),
        ),
      ),
    getSample: (sampleId) =>
      call("get_sample", { sample_id: sampleId }, (value) => {
        const row = recordOf(value, "get_sample");

        return {
          ...sampleOf(row, "get_sample"),
          results: recordsOf(row["results"], "get_sample").map((entry) =>
            resultOf(entry, "get_sample"),
          ),
        };
      }),
    listSamples: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_samples",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_samples").map((row) =>
              sampleOf(row, "list_samples"),
            ),
        ),
      ),
    recordResult: (sampleId, methodId, input) =>
      call(
        "record_lims_result",
        {
          sample_id: sampleId,
          method_id: methodId,
          input: definedOf({ ...input, testedAt: input.testedAt?.toString() }),
        },
        (value) => resultOf(value, "record_lims_result"),
      ),
    completeSample: (sampleId) =>
      call("complete_sample", { sample_id: sampleId }, (value) =>
        sampleOf(value, "complete_sample"),
      ),
    releaseSample: (sampleId) =>
      call("release_sample", { sample_id: sampleId }, (value) =>
        sampleOf(value, "release_sample"),
      ),
    rejectSample: (sampleId, reason) =>
      call("reject_sample", { sample_id: sampleId, reason }, (value) =>
        sampleOf(value, "reject_sample"),
      ),
    instrumentStatus: (assetId, on) =>
      tenant().andThen((organizationId) =>
        call(
          "instrument_status",
          {
            tenant: organizationId,
            asset_id: assetId,
            ...(on === undefined ? {} : { on_date: on.toString() }),
          },
          (value) => {
            const row = recordOf(value, "instrument_status");

            return {
              instrumentId: textOf(row["instrumentId"]),
              required: row["required"] === true,
              qualified: row["qualified"] === true,
            };
          },
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "lims",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
