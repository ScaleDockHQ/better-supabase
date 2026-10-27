import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { compact } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type SlaMetric = "first_response" | "next_response" | "resolution";

export type SlaState = "running" | "paused" | "met" | "breached";

/** What happened on a record, moving its clocks. */
export type SlaEvent =
  | "responded"
  | "resolved"
  | "reopened"
  | "paused"
  | "resumed";

const METRICS: readonly SlaMetric[] = [
  "first_response",
  "next_response",
  "resolution",
];

const STATES: readonly SlaState[] = ["running", "paused", "met", "breached"];

/** A policy. `F` types the extra columns the `fields` schema describes. */
export interface SlaPolicy<F extends object = Record<never, never>> {
  readonly id: string;
  readonly subjectType: string;
  readonly name: string;
  /** The priority it covers; `undefined` covers every priority. */
  readonly priority?: string;
  readonly firstResponseMinutes?: number;
  readonly nextResponseMinutes?: number;
  readonly resolutionMinutes?: number;
  /** The share of the time after which a clock warns. */
  readonly warnAtPercent: number;
  /** Count only the module's business hours. */
  readonly businessHours: boolean;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface SlaClock {
  readonly id: string;
  readonly subject: RecordRef;
  readonly metric: SlaMetric;
  readonly state: SlaState;
  readonly startedAt: Temporal.Instant;
  readonly dueAt: Temporal.Instant;
  /** Until the due time; negative once breached, undefined once met. */
  readonly secondsLeft?: number;
  readonly pausedAt?: Temporal.Instant;
  readonly warnedAt?: Temporal.Instant;
  readonly breachedAt?: Temporal.Instant;
  readonly metAt?: Temporal.Instant;
}

export interface SlaPolicyInput<F extends object = Record<never, never>> {
  readonly id?: string;
  readonly subjectType?: string;
  readonly name?: string;
  readonly priority?: string | null;
  readonly firstResponseMinutes?: number | null;
  readonly nextResponseMinutes?: number | null;
  readonly resolutionMinutes?: number | null;
  readonly warnAtPercent?: number;
  readonly businessHours?: boolean;
  readonly archived?: boolean;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface Sla<F extends object = Record<never, never>> {
  /** Creates or updates a policy in the block's `tenant`. */
  savePolicy(policy: SlaPolicyInput<F>): AsyncResult<SlaPolicy<F>>;
  /**
   * Starts a record's clocks, or recomputes them for a new priority. The tenant
   * comes from the record.
   */
  start(subject: RecordRef, priority?: string): AsyncResult<SlaClock[]>;
  /** Moves a record's clocks: a reply, a resolution, a pause. */
  record(subject: RecordRef, event: SlaEvent): AsyncResult<SlaClock[]>;
  clocks(subject: RecordRef): AsyncResult<SlaClock[]>;
  /** Records warnings and breaches. Service role only; run it from a job. */
  check(): AsyncResult<number>;
  /** The time `minutes` of working time after `start`. */
  dueAt(
    start: Temporal.Instant,
    minutes: number,
    businessHours: boolean,
  ): AsyncResult<Temporal.Instant>;
}

export interface SlaOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the policy's extra columns
   * (`blocks.sla.options.extraColumns`), keyed by database name. It types and
   * parses them on `savePolicy`, and validates them before the write.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Sla<FieldsOf<S>>>>;
  readonly logger?: Logger;
}

const minutes = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function policyOf(value: unknown): SlaPolicy {
  const row = recordOf(value, "sla policy");

  return compact<SlaPolicy>({
    id: textOf(row["id"]),
    subjectType: textOf(row["subject_type"]),
    name: textOf(row["name"]),
    priority: optionalText(row["priority"]),
    firstResponseMinutes: minutes(row["first_response_minutes"]),
    nextResponseMinutes: minutes(row["next_response_minutes"]),
    resolutionMinutes: minutes(row["resolution_minutes"]),
    warnAtPercent: minutes(row["warn_at_percent"]) ?? 80,
    businessHours: row["business_hours"] === true,
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  });
}

function clockOf(value: unknown): SlaClock {
  const row = recordOf(value, "sla clock");

  return compact<SlaClock>({
    id: textOf(row["id"]),
    subject: subjectRefOf(row["subject_type"], row["subject_id"]),
    metric: enumOrThrow(row["metric"], METRICS, "sla metric"),
    state: enumOrThrow(row["state"], STATES, "sla state"),
    startedAt: requiredInstant(row["started_at"], "startedAt"),
    dueAt: requiredInstant(row["due_at"], "dueAt"),
    secondsLeft: minutes(row["secondsLeft"]),
    pausedAt: optionalInstant(row["paused_at"]),
    warnedAt: optionalInstant(row["warned_at"]),
    breachedAt: optionalInstant(row["breached_at"]),
    metAt: optionalInstant(row["met_at"]),
  });
}

const clocks = (value: unknown): SlaClock[] =>
  recordsOf(value, "sla clocks").map(clockOf);

/**
 * The sla block: response and resolution clocks on any record, from a policy
 * per record type and priority.
 */
export function createSla<S extends StandardSchemaV1 | undefined = undefined>(
  options: SlaOptions<S>,
): Sla<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "sla policy fields",
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Sla<F> = {
    savePolicy: (policy) => {
      const { id, fields: extra, ...attrs } = policy;

      return tenant().andThen((organizationId) =>
        fields
          .args(extra)
          .andThen((checked) =>
            call(
              "save_sla_policy",
              {
                tenant: organizationId,
                policy: id ?? null,
                attrs:
                  checked === undefined ? attrs : { ...attrs, fields: checked },
              },
              policyOf,
            ).andThen(fields.row),
          ),
      );
    },
    start: (subject, priority) =>
      call(
        "start_sla_clocks",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          priority: priority ?? null,
        },
        clocks,
      ),
    record: (subject, event) =>
      call(
        "record_sla_event",
        { subject_type: subject.type, subject_id: subject.id, event },
        clocks,
      ),
    clocks: (subject) =>
      call(
        "sla_clocks_of",
        { subject_type: subject.type, subject_id: subject.id },
        clocks,
      ),
    check: () => call("check_sla_clocks", {}, (value) => Number(value ?? 0)),
    dueAt: (start, total, businessHours) =>
      call(
        "sla_due_at",
        { start: instantArg(start), minutes: total, business: businessHours },
        (value) => requiredInstant(value, "sla_due_at"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "sla",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
