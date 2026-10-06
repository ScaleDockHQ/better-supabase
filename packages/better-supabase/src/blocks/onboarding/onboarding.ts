import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import {
  blockCall,
  optionalInstant,
  optionalText,
  recordsOf,
  textOf,
} from "../shared.ts";

export type ChecklistScope = "user" | "organization";

/** One step. `events` completes it when the outbox records one of those types. */
export interface ChecklistStep<Id extends string = string> {
  readonly id: Id;
  readonly title?: string;
  readonly description?: string;
  /** Where the step is done in the app, for a "Start" link. */
  readonly href?: string;
  readonly events?: readonly string[];
}

export interface ChecklistSpec<
  Id extends string,
  Scope extends ChecklistScope,
> {
  readonly id: string;
  /** `user` tracks each user; `organization` tracks each tenant. */
  readonly scope: Scope;
  readonly steps: readonly ChecklistStep<Id>[];
}

export interface ChecklistConnectOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.onboarding.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** A step with the subject's progress. */
export interface StepProgress<Id extends string> extends ChecklistStep<Id> {
  readonly completed: boolean;
  readonly completedAt: Temporal.Instant | undefined;
  readonly completedBy: string | undefined;
}

export interface ChecklistProgress<Id extends string> {
  readonly steps: readonly StepProgress<Id>[];
  readonly completed: number;
  readonly total: number;
  /** Every step is complete. */
  readonly done: boolean;
  /** The first step not done yet. */
  readonly next: StepProgress<Id> | undefined;
}

/** The organization for an organization checklist; nothing for a user one. */
export type ChecklistSubject<Scope extends ChecklistScope> =
  Scope extends "organization" ? [organizationId: string] : [];

export interface ChecklistClient<
  Id extends string,
  Scope extends ChecklistScope,
> {
  progress(
    ...subject: ChecklistSubject<Scope>
  ): AsyncResult<ChecklistProgress<Id>>;
  /** Marks a step done; `false` when it already was. */
  complete(step: Id, ...subject: ChecklistSubject<Scope>): AsyncResult<boolean>;
  /** Marks a step not done; `false` when it wasn't. */
  reset(step: Id, ...subject: ChecklistSubject<Scope>): AsyncResult<boolean>;
}

export interface Checklist<
  Id extends string,
  Scope extends ChecklistScope,
> extends ChecklistSpec<Id, Scope> {
  connect(options: ChecklistConnectOptions): ChecklistClient<Id, Scope>;
}

const ID = /^[a-z][a-z0-9_.-]{0,63}$/;

/**
 * Declares an onboarding checklist. Pass the result to
 * `sql.modules.onboarding.options.checklists` so the database knows its
 * steps, and `connect` it to read and complete them.
 */
export function defineChecklist<
  const Id extends string,
  const Scope extends ChecklistScope,
>(spec: ChecklistSpec<Id, Scope>): Checklist<Id, Scope> {
  if (!ID.test(spec.id)) {
    throw new TypeError(`defineChecklist: "${spec.id}" is not a checklist id`);
  }
  const seen = new Set<string>();
  for (const step of spec.steps) {
    if (!ID.test(step.id) || seen.has(step.id)) {
      throw new TypeError(
        `defineChecklist(${spec.id}): step "${step.id}" is not a unique step id`,
      );
    }
    seen.add(step.id);
  }
  return {
    ...spec,
    connect: (options) => connectChecklist(spec, options),
  };
}

function connectChecklist<Id extends string, Scope extends ChecklistScope>(
  spec: ChecklistSpec<Id, Scope>,
  options: ChecklistConnectOptions,
): ChecklistClient<Id, Scope> {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenantOf = (subject: readonly string[]) => ({
    tenant: subject[0] ?? null,
  });
  return {
    progress: (...subject) =>
      call(
        "onboarding_progress",
        { checklist: spec.id, ...tenantOf(subject) },
        (value) => progressOf(spec.steps, value),
      ),
    complete: (step, ...subject) =>
      call(
        "complete_onboarding_step",
        { checklist: spec.id, step, ...tenantOf(subject) },
        (value) => value === true,
      ),
    reset: (step, ...subject) =>
      call(
        "reset_onboarding_step",
        { checklist: spec.id, step, ...tenantOf(subject) },
        (value) => value === true,
      ),
  };
}

function progressOf<Id extends string>(
  steps: readonly ChecklistStep<Id>[],
  value: unknown,
): ChecklistProgress<Id> {
  const rows = new Map(
    recordsOf(value, "onboarding_progress").map((row) => [
      textOf(row["step"]),
      row,
    ]),
  );
  const list = steps.map((step): StepProgress<Id> => {
    const row = rows.get(step.id);
    return {
      ...step,
      completed: row !== undefined,
      completedAt: optionalInstant(row?.["completedAt"]),
      completedBy: optionalText(row?.["completedBy"]),
    };
  });
  const completed = list.filter((step) => step.completed).length;
  return {
    steps: list,
    completed,
    total: list.length,
    done: completed === list.length,
    next: list.find((step) => !step.completed),
  };
}
