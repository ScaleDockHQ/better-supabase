import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  type CursorPageOptions,
  instantArg,
  optionalInstant,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

export interface StateMachineOptions<
  S extends string = string,
> extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<StateMachine<S>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Where a record is in its machine, from `state()`. */
export interface StatusState {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly status: string;
  /** The machine's `order`, empty when it sets none. */
  readonly order: readonly string[];
  /** The status's 1-based position in `order`, `undefined` outside it. */
  readonly step: number | undefined;
  readonly steps: number | undefined;
  /** 0 at the first status of `order`, 1 at the last, `undefined` outside it. */
  readonly progress: number | undefined;
  /**
   * The machine version the record is pinned to. `undefined` without
   * `lifecycle: true`, or for a record created before it was on and never
   * paused or flagged since.
   */
  readonly version: number | undefined;
  readonly flags: readonly string[];
  /** True while a pause holds: no end, or an end still in the future. */
  readonly paused: boolean;
  readonly pausedAt: Temporal.Instant | undefined;
  readonly pausedUntil: Temporal.Instant | undefined;
  readonly pauseReason: string | undefined;
}

/** One status change from `history()`. */
export interface StatusChange {
  readonly id: string;
  /** `undefined` for the first status of a history table that records it. */
  readonly from: string | undefined;
  readonly to: string;
  readonly actorId: string | undefined;
  readonly reason: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** One row of a machine's stages timeline, from `stages()`. */
export interface StatusStage {
  readonly id: string;
  readonly label: string;
  readonly outcome: string | undefined;
  readonly display: number;
  /** When the record moved on from this stage; `undefined` for the open one. */
  readonly clearedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface StateMachine<S extends string = string> {
  /**
   * Sets the status as the caller: the record table's policies decide whether
   * they may update it, and the trigger rejects a change the machine does not
   * allow. `not_found` for a record they can't see.
   */
  transition(
    subjectType: S,
    subjectId: string,
    to: string,
    reason?: string,
  ): AsyncResult<boolean>;
  /**
   * Pauses the record (`lifecycle: true`): transitions fail with `STATE_PAUSED`
   * until `until` passes, or until `resume()` without one.
   */
  pause(
    subjectType: S,
    subjectId: string,
    options?: { readonly until?: Temporal.Instant; readonly reason?: string },
  ): AsyncResult<boolean>;
  /** Ends a pause; `false` when the record wasn't paused. */
  resume(subjectType: S, subjectId: string): AsyncResult<boolean>;
  /**
   * Turns a flag the machine lists in `flags` on or off; `false` when it
   * already was.
   */
  setFlag(
    subjectType: S,
    subjectId: string,
    flag: string,
    enabled: boolean,
  ): AsyncResult<boolean>;
  /** The record's status, progress, flags, pause and pinned version. */
  state(subjectType: S, subjectId: string): AsyncResult<StatusState>;
  /**
   * Status changes, newest first; page with the last `createdAt` as `cursor`.
   * Default 50, at most 500.
   */
  history(
    subjectType: S,
    subjectId: string,
    page?: CursorPageOptions<Temporal.Instant>,
  ): AsyncResult<readonly StatusChange[]>;
  /**
   * The stages timeline in display order; empty for a machine without `stages:
   * true`.
   */
  stages(
    subjectType: S,
    subjectId: string,
  ): AsyncResult<readonly StatusStage[]>;
}

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

function stateOf(value: unknown): StatusState {
  const row = recordOf(value, "status_state");

  return {
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    status: textOf(row["status"]),
    order: stringsOf(row["order"]),
    step: optionalNumber(row["step"]),
    steps: optionalNumber(row["steps"]),
    progress: optionalNumber(row["progress"]),
    version: optionalNumber(row["version"]),
    flags: stringsOf(row["flags"]),
    paused: row["paused"] === true,
    pausedAt: optionalInstant(row["pausedAt"]),
    pausedUntil: optionalInstant(row["pausedUntil"]),
    pauseReason: optionalText(row["pauseReason"]),
  };
}

function changeOf(row: Record<string, unknown>): StatusChange {
  return {
    id: textOf(row["id"]),
    from: optionalText(row["from"]),
    to: textOf(row["to"]),
    actorId: optionalText(row["actorId"]),
    reason: optionalText(row["reason"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function stageOf(row: Record<string, unknown>): StatusStage {
  return {
    id: textOf(row["id"]),
    label: textOf(row["label"]),
    outcome: optionalText(row["outcome"]),
    display: Number(row["display"]),
    clearedAt: optionalInstant(row["clearedAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

/** The `state-machine` SQL module as typed calls. */
export function createStateMachine<S extends string = string>(
  options: StateMachineOptions<S>,
): StateMachine<S> {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const isTrue = (value: unknown): boolean => value === true;

  const client: StateMachine<S> = {
    transition: (subjectType, subjectId, to, reason) =>
      call(
        "transition",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          to_status: to,
          reason: reason ?? null,
        },
        isTrue,
      ),
    pause: (subjectType, subjectId, pause = {}) =>
      call(
        "pause_lifecycle",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          until: instantArg(pause.until) ?? null,
          reason: pause.reason ?? null,
        },
        isTrue,
      ),
    resume: (subjectType, subjectId) =>
      call(
        "resume_lifecycle",
        { subject_type: subjectType, subject_id: subjectId },
        isTrue,
      ),
    setFlag: (subjectType, subjectId, flag, enabled) =>
      call(
        "set_lifecycle_flag",
        { subject_type: subjectType, subject_id: subjectId, flag, enabled },
        isTrue,
      ),
    state: (subjectType, subjectId) =>
      call(
        "status_state",
        { subject_type: subjectType, subject_id: subjectId },
        stateOf,
      ),
    history: (subjectType, subjectId, page) =>
      call(
        "list_status_history",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          before: instantArg(pageOf(page).cursor),
          max_rows: page?.limit,
        },
        (value) => recordsOf(value, "list_status_history").map(changeOf),
      ),
    stages: (subjectType, subjectId) =>
      call(
        "list_status_stages",
        { subject_type: subjectType, subject_id: subjectId },
        (value) => recordsOf(value, "list_status_stages").map(stageOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "state-machine",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
