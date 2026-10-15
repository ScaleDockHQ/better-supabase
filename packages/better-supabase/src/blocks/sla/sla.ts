import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { compact } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
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

export interface SlaPolicy {
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
}

export interface SlaClock {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
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

export interface SlaPolicyInput {
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
}

export interface Sla {
  savePolicy(
    organizationId: string,
    policy: SlaPolicyInput,
  ): AsyncResult<SlaPolicy>;
  /** Starts a record's clocks, or recomputes them for a new priority. */
  start(
    subject: { readonly type: string; readonly id: string },
    priority?: string,
  ): AsyncResult<SlaClock[]>;
  /** Moves a record's clocks: a reply, a resolution, a pause. */
  record(
    subject: { readonly type: string; readonly id: string },
    event: SlaEvent,
  ): AsyncResult<SlaClock[]>;
  clocks(subject: {
    readonly type: string;
    readonly id: string;
  }): AsyncResult<SlaClock[]>;
  /** Records warnings and breaches. Service role only; run it from a job. */
  check(): AsyncResult<number>;
  /** The time `minutes` of working time after `start`. */
  dueAt(
    start: Temporal.Instant,
    minutes: number,
    businessHours: boolean,
  ): AsyncResult<Temporal.Instant>;
}

export interface SlaOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Sla>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
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
  });
}

function clockOf(value: unknown): SlaClock {
  const row = recordOf(value, "sla clock");
  return compact<SlaClock>({
    id: textOf(row["id"]),
    subjectType: textOf(row["subject_type"]),
    subjectId: textOf(row["subject_id"]),
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
 * The sla block: response and resolution clocks on any record, from a
 * policy per record type and priority.
 */
export function createSla(options: SlaOptions): Sla {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Sla = {
    savePolicy: (organizationId, policy) => {
      const { id, ...attrs } = policy;
      return call(
        "save_sla_policy",
        { tenant: organizationId, policy: id ?? null, attrs },
        policyOf,
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
