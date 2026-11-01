import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  blockCall,
  optionalInstant,
  optionalText,
  recordsOf,
  textOf,
  applyTemporal,
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

export interface OnboardingOptions extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Onboarding>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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
  Scope extends "organization"
    ? { readonly organizationId: string }
    : { readonly organizationId?: undefined };

/**
 * The onboarding block: progress through any checklist `defineChecklist`
 * declared.
 */
export interface Onboarding {
  /**
   * The subject's progress: the caller's for a user checklist, the
   * organization's otherwise.
   */
  progress<Id extends string, Scope extends ChecklistScope>(
    input: {
      readonly checklist: Checklist<Id, Scope>;
    } & ChecklistSubject<Scope>,
  ): AsyncResult<ChecklistProgress<Id>>;
  /** Marks a step done; `false` when it already was. */
  complete<Id extends string, Scope extends ChecklistScope>(
    input: {
      readonly checklist: Checklist<Id, Scope>;
      readonly step: Id;
    } & ChecklistSubject<Scope>,
  ): AsyncResult<boolean>;
  /** Marks a step not done; `false` when it wasn't. */
  reset<Id extends string, Scope extends ChecklistScope>(
    input: {
      readonly checklist: Checklist<Id, Scope>;
      readonly step: Id;
    } & ChecklistSubject<Scope>,
  ): AsyncResult<boolean>;
}

/**
 * A checklist `defineChecklist` checked; pass it to the onboarding client's
 * methods.
 */
export type Checklist<
  Id extends string,
  Scope extends ChecklistScope,
> = ChecklistSpec<Id, Scope>;

const ID = /^[a-z][a-z0-9_.-]{0,63}$/;

/**
 * Declares an onboarding checklist. Pass the result to
 * `blocks.onboarding.options.checklists` so the database knows its steps, and
 * to the methods of `createOnboarding` to read and complete them.
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

  return spec;
}

/**
 * The onboarding block: reads and completes the steps of the checklists in
 * `blocks.onboarding.options.checklists`, for the caller or an organization.
 */
export function createOnboarding(options: OnboardingOptions): Onboarding {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const tenantOf = (subject: {
    readonly organizationId?: string | undefined;
  }) => ({ tenant: subject.organizationId ?? null });

  const client: Onboarding = {
    progress: ({ checklist, ...subject }) =>
      call(
        "onboarding_progress",
        { checklist: checklist.id, ...tenantOf(subject) },
        (value) => progressOf(checklist.steps, value),
      ),
    complete: ({ checklist, step, ...subject }) =>
      call(
        "complete_onboarding_step",
        { checklist: checklist.id, step, ...tenantOf(subject) },
        (value) => value === true,
      ),
    reset: ({ checklist, step, ...subject }) =>
      call(
        "reset_onboarding_step",
        { checklist: checklist.id, step, ...tenantOf(subject) },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "onboarding",
    ...(options.logger ? { logger: options.logger } : {}),
  });
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
