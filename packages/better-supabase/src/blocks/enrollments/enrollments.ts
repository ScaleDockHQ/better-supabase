import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface EnrollmentsOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Enrollments>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const STATUSES = ["active", "completed", "cancelled"] as const;

/** Where an enrollment stands. A cancelled one keeps its completed steps. */
export type EnrollmentStatus = (typeof STATUSES)[number];

/** Who a step is for: members with a role, or one user. */
export type EnrollmentAssignee =
  | { readonly role: string }
  | { readonly userId: string };

/**
 * When a step is due: whole days (from -3650 to 3650) after the enrollment's
 * start or end. The start falls back to when it enrolled; a step due from the
 * end has no due date until the enrollment has one.
 */
export interface EnrollmentDue {
  readonly days: number;
  readonly from: "start" | "end";
}

/** A step of a program. */
export interface EnrollmentStep {
  /** Lowercase letters, digits, `_`, `.` or `-`, starting with a letter. */
  readonly id: string;
  readonly title?: string;
  readonly description?: string;
  readonly assignee?: EnrollmentAssignee;
  readonly due?: EnrollmentDue;
}

/** A program of steps that subjects enroll in. */
export interface EnrollmentProgram {
  readonly id: string;
  readonly organizationId: string;
  /** Unique in the organization; it can't change. */
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  /** The subject types it enrolls; empty enrolls any. */
  readonly subjectTypes: readonly string[];
  readonly steps: readonly EnrollmentStep[];
  readonly enabled: boolean;
  /** Raised each time the steps change. */
  readonly version: number;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A program to create (without `id`) or change (with it). */
export interface EnrollmentProgramInput {
  readonly id?: string;
  /**
   * The version you read; a stale one fails with
   * `ENROLLMENTS_PROGRAM_CONFLICT`.
   */
  readonly version?: number;
  readonly key?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly subjectTypes?: readonly string[];
  readonly steps?: readonly EnrollmentStep[];
  readonly enabled?: boolean;
}

/** A completed step of an enrollment. */
export interface EnrollmentProgress {
  readonly step: string;
  readonly completedAt: Temporal.Instant;
  readonly completedBy?: string;
}

/** A step of an enrollment with an assignee or a due date. */
export interface EnrollmentScheduledStep {
  readonly step: string;
  readonly assignee?: EnrollmentAssignee;
  /** Rendered from the step's `due` and the enrollment's dates. */
  readonly dueAt?: Temporal.Instant;
  /** Set once the step is done. */
  readonly completedAt?: Temporal.Instant;
}

/** An open step with an assignee or a due date, from `openSteps`. */
export interface EnrollmentOpenStep {
  readonly enrollmentId: string;
  readonly organizationId: string;
  readonly program: string;
  readonly subject: RecordRef;
  readonly step: string;
  readonly title?: string;
  readonly assignee?: EnrollmentAssignee;
  readonly dueAt?: Temporal.Instant;
}

/** The dates an enrollment's due dates count from; `null` clears one. */
export interface EnrollmentDates {
  readonly startsAt?: Temporal.Instant | null;
  readonly endsAt?: Temporal.Instant | null;
}

export interface EnrollmentOpenStepsFilter {
  /** Steps assigned to this role. */
  readonly role?: string;
  /** Steps assigned to this user. */
  readonly userId?: string;
  /** Steps due before this instant. */
  readonly dueBefore?: Temporal.Instant;
  /** Default 50, at most 200. */
  readonly pageSize?: number;
}

/** A subject's enrollment in a program, with its completed steps. */
export interface Enrollment {
  readonly id: string;
  /** Unset for a user's own onboarding checklist. */
  readonly organizationId?: string;
  /** The program key; `onboarding:<checklist>` for an onboarding checklist. */
  readonly program: string;
  readonly programVersion?: number;
  readonly subject: RecordRef;
  readonly status: EnrollmentStatus;
  /** The program's step ids when it enrolled or last changed. */
  readonly steps: readonly string[];
  readonly completedSteps: number;
  readonly totalSteps: number;
  /** Oldest first. */
  readonly progress: readonly EnrollmentProgress[];
  /** The steps with an assignee or a due date, in step order. */
  readonly schedule: readonly EnrollmentScheduledStep[];
  readonly enrolledBy?: string;
  readonly enrolledAt: Temporal.Instant;
  /** When it starts; due dates from the start fall back to `enrolledAt`. */
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  /** When a module, such as a sequence, paused it; unset while it runs. */
  readonly pausedAt?: Temporal.Instant;
  /** Why a module ended it, such as a sequence's exit reason. */
  readonly cancelReason?: string;
  readonly updatedAt: Temporal.Instant;
}

export interface EnrollmentsFilter {
  readonly program?: string;
  readonly subject?: RecordRef;
  readonly status?: EnrollmentStatus;
  /** Default 50, at most 200. */
  readonly pageSize?: number;
  /** Enrollments changed before this instant, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Enrollments {
  /** Creates or changes a program; changing its steps raises its version. */
  saveProgram(program: EnrollmentProgramInput): AsyncResult<EnrollmentProgram>;
  /** The organization's programs by key. */
  programs(): AsyncResult<readonly EnrollmentProgram[]>;
  /** Deletes a program with its enrollments; `false` when it was gone. */
  deleteProgram(programId: string): AsyncResult<boolean>;
  /**
   * Enrolls a subject. An enrolled subject keeps its enrollment, and a
   * cancelled one starts again with its completed steps. With `dates`, it sets
   * them as `setDates` does.
   */
  enroll(input: {
    program: string;
    subject: RecordRef;
    dates?: EnrollmentDates | undefined;
  }): AsyncResult<Enrollment>;
  /** Sets the dates its due dates count from and renders them again. */
  setDates(input: {
    enrollmentId: string;
    dates: EnrollmentDates;
  }): AsyncResult<Enrollment>;
  /**
   * Open steps of active enrollments that have an assignee or a due date,
   * soonest due first. Without `enrollments.read`, the caller's own.
   */
  openSteps(
    filter?: EnrollmentOpenStepsFilter,
  ): AsyncResult<readonly EnrollmentOpenStep[]>;
  /** A subject's enrollment in a program, or `null`. */
  enrollment(input: {
    program: string;
    subject: RecordRef;
  }): AsyncResult<Enrollment | null>;
  /**
   * The organization's enrollments, most recently changed first. Without
   * `enrollments.read`, the caller's own.
   */
  list(filter?: EnrollmentsFilter): AsyncResult<readonly Enrollment[]>;
  /** Marks a step done; completing the last step completes the enrollment. */
  complete(input: {
    enrollmentId: string;
    step: string;
  }): AsyncResult<Enrollment>;
  /** Marks a step not done again. */
  reset(input: { enrollmentId: string; step: string }): AsyncResult<Enrollment>;
  /** Cancels an active enrollment; its completed steps stay. */
  cancel(enrollmentId: string): AsyncResult<Enrollment>;
  /** Resets every completed step, so the enrollment runs from the start. */
  restart(enrollmentId: string): AsyncResult<Enrollment>;
  /**
   * Completes the first step that isn't done yet, in the program's order. Fails
   * with `not_found` when every step is done.
   */
  advance(input: {
    enrollmentId: string;
    subject: RecordRef;
    program: string;
  }): AsyncResult<Enrollment>;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> {
  if (value === undefined) {
    return {};
  }

  const out: Partial<Record<K, V>> = {};
  out[key] = value;

  return out;
}

const texts = (value: unknown): readonly string[] =>
  Array.isArray(value) ? value.map((item) => textOf(item)) : [];

const FROM = ["start", "end"] as const;

function assigneeOf(value: unknown): EnrollmentAssignee | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const role = optionalText(value["role"]);

  if (role !== undefined) {
    return { role };
  }

  const userId = optionalText(value["userId"]);

  return userId === undefined ? undefined : { userId };
}

function dueOf(value: unknown): EnrollmentDue | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    days: Number(value["days"] ?? 0),
    from: enumOrThrow(value["from"], FROM, "due date anchor"),
  };
}

function stepOf(value: unknown, fn: string): EnrollmentStep {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    ...optional("title", optionalText(row["title"])),
    ...optional("description", optionalText(row["description"])),
    ...optional("assignee", assigneeOf(row["assignee"])),
    ...optional("due", dueOf(row["due"])),
  };
}

function scheduledOf(value: unknown, fn: string): EnrollmentScheduledStep {
  const row = recordOf(value, fn);

  return {
    step: textOf(row["step"]),
    ...optional("assignee", assigneeOf(row["assignee"])),
    ...optional("dueAt", optionalInstant(row["dueAt"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
  };
}

function openStepOf(value: unknown, fn: string): EnrollmentOpenStep {
  const row = recordOf(value, fn);

  return {
    enrollmentId: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    program: textOf(row["program"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    step: textOf(row["step"]),
    ...optional("title", optionalText(row["title"])),
    ...optional("assignee", assigneeOf(row["assignee"])),
    ...optional("dueAt", optionalInstant(row["dueAt"])),
  };
}

function datesArg(dates: EnrollmentDates): Record<string, string | null> {
  return {
    ...optional("startsAt", instantArg(dates.startsAt)),
    ...optional("endsAt", instantArg(dates.endsAt)),
  };
}

function programOf(value: unknown, fn: string): EnrollmentProgram {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    subjectTypes: texts(row["subjectTypes"]),
    steps: recordsOf(row["steps"] ?? [], fn).map((step) => stepOf(step, fn)),
    enabled: row["enabled"] !== false,
    version: Number(row["version"] ?? 1),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function progressOf(value: unknown, fn: string): EnrollmentProgress {
  const row = recordOf(value, fn);

  return {
    step: textOf(row["step"]),
    completedAt: requiredInstant(row["completedAt"], "completedAt"),
    ...optional("completedBy", optionalText(row["completedBy"])),
  };
}

function enrollmentOf(value: unknown, fn: string): Enrollment {
  const row = recordOf(value, fn);
  const version = row["programVersion"];

  return {
    id: textOf(row["id"]),
    program: textOf(row["program"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    status: enumOrThrow(row["status"], STATUSES, "enrollment status"),
    steps: texts(row["steps"]),
    completedSteps: Number(row["completedSteps"] ?? 0),
    totalSteps: Number(row["totalSteps"] ?? 0),
    progress: recordsOf(row["progress"] ?? [], fn).map((item) =>
      progressOf(item, fn),
    ),
    schedule: recordsOf(row["schedule"] ?? [], fn).map((item) =>
      scheduledOf(item, fn),
    ),
    enrolledAt: requiredInstant(row["enrolledAt"], "enrolledAt"),
    ...optional("startsAt", optionalInstant(row["startsAt"])),
    ...optional("endsAt", optionalInstant(row["endsAt"])),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("organizationId", optionalText(row["organizationId"])),
    ...optional(
      "programVersion",
      typeof version === "number" ? version : undefined,
    ),
    ...optional("enrolledBy", optionalText(row["enrolledBy"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("cancelledAt", optionalInstant(row["cancelledAt"])),
    ...optional("pausedAt", optionalInstant(row["pausedAt"])),
    ...optional("cancelReason", optionalText(row["cancelReason"])),
  };
}

function programArg(program: EnrollmentProgramInput): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(program)) {
    if (value !== undefined) {
      out[key] = value;
    }
  }

  return out;
}

/** The `enrollments` SQL module as typed calls. */
export function createEnrollments(options: EnrollmentsOptions): Enrollments {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const one =
    (fn: string) =>
    (value: unknown): Enrollment =>
      enrollmentOf(value, fn);

  const setDates = (
    enrollmentId: string,
    dates: EnrollmentDates,
  ): AsyncResult<Enrollment> =>
    call(
      "set_enrollment_dates",
      { enrollment_id: enrollmentId, dates: datesArg(dates) },
      one("set_enrollment_dates"),
    );

  const client: Enrollments = {
    saveProgram: (program) =>
      tenant().andThen((organizationId) =>
        call(
          "save_enrollment_program",
          { tenant: organizationId, program: programArg(program) },
          (value) => programOf(value, "save_enrollment_program"),
        ),
      ),
    programs: () =>
      tenant().andThen((organizationId) =>
        call("enrollment_programs", { tenant: organizationId }, (value) =>
          recordsOf(value, "enrollment_programs").map((row) =>
            programOf(row, "enrollment_programs"),
          ),
        ),
      ),
    deleteProgram: (programId) =>
      call(
        "delete_enrollment_program",
        { program_id: programId },
        (value) => value === true,
      ),
    enroll: ({ program, subject, dates }) =>
      tenant()
        .andThen((organizationId) =>
          call(
            "enroll",
            {
              tenant: organizationId,
              program,
              subject_type: subject.type,
              subject_id: subject.id,
            },
            one("enroll"),
          ),
        )
        .andThen((enrollment) =>
          dates === undefined
            ? AsyncResult.ok(enrollment)
            : setDates(enrollment.id, dates),
        ),
    setDates: ({ enrollmentId, dates }) => setDates(enrollmentId, dates),
    openSteps: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "open_enrollment_steps",
          {
            tenant: organizationId,
            assignee_role: filter.role ?? null,
            assignee_user: filter.userId ?? null,
            due_before: instantArg(filter.dueBefore) ?? null,
            page_size: filter.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "open_enrollment_steps").map((row) =>
              openStepOf(row, "open_enrollment_steps"),
            ),
        ),
      ),
    enrollment: ({ program, subject }) =>
      tenant().andThen((organizationId) =>
        call(
          "enrollment",
          {
            tenant: organizationId,
            program,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) =>
            isRecord(value) ? enrollmentOf(value, "enrollment") : null,
        ),
      ),
    list: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_enrollments",
          {
            tenant: organizationId,
            program: filter.program ?? null,
            subject_type: filter.subject?.type ?? null,
            subject_id: filter.subject?.id ?? null,
            status: filter.status ?? null,
            page_size: filter.pageSize ?? null,
            before: instantArg(filter.before) ?? null,
          },
          (value) =>
            recordsOf(value, "list_enrollments").map((row) =>
              enrollmentOf(row, "list_enrollments"),
            ),
        ),
      ),
    complete: ({ enrollmentId, step }) =>
      call(
        "complete_enrollment_step",
        { enrollment_id: enrollmentId, step },
        one("complete_enrollment_step"),
      ),
    reset: ({ enrollmentId, step }) =>
      call(
        "reset_enrollment_step",
        { enrollment_id: enrollmentId, step },
        one("reset_enrollment_step"),
      ),
    cancel: (enrollmentId) =>
      call(
        "cancel_enrollment",
        { enrollment_id: enrollmentId },
        one("cancel_enrollment"),
      ),
    restart: (enrollmentId) =>
      AsyncResult.from(async () => {
        const found = await hooked.list({ pageSize: 200 });

        if (!found.ok) {
          return found;
        }

        const enrollment = found.data.find((each) => each.id === enrollmentId);

        if (enrollment === undefined) {
          return err(
            dbError("not_found", `Enrollment ${enrollmentId} not found`),
          );
        }

        let latest = enrollment;

        for (const { step } of enrollment.progress) {
          const reset = await hooked.reset({ enrollmentId, step });

          if (!reset.ok) {
            return reset;
          }

          latest = reset.data;
        }

        return ok(latest);
      }),
    advance: ({ enrollmentId, subject, program }) =>
      hooked.enrollment({ program, subject }).andThen(async (enrollment) => {
        if (enrollment === null || enrollment.id !== enrollmentId) {
          return err(
            dbError("not_found", `Enrollment ${enrollmentId} not found`),
          );
        }

        const done = new Set(enrollment.progress.map((each) => each.step));
        const next = enrollment.steps.find((step) => !done.has(step));

        if (next === undefined) {
          return err(dbError("not_found", "Every step is done"));
        }

        return hooked.complete({ enrollmentId, step: next });
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Enrollments = withBlockHooks(client, options.hooks, {
    block: "enrollments",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
