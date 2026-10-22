import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
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

/** A step of a program. */
export interface EnrollmentStep {
  /** Lowercase letters, digits, `_`, `.` or `-`, starting with a letter. */
  readonly id: string;
  readonly title?: string;
  readonly description?: string;
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

/** A subject's enrollment in a program, with its completed steps. */
export interface Enrollment {
  readonly id: string;
  /** Unset for a user's own onboarding checklist. */
  readonly organizationId?: string;
  /** The program key; `onboarding:<checklist>` for an onboarding checklist. */
  readonly program: string;
  readonly programVersion?: number;
  readonly subject: SubjectRef;
  readonly status: EnrollmentStatus;
  /** The program's step ids when it enrolled or last changed. */
  readonly steps: readonly string[];
  readonly completedSteps: number;
  readonly totalSteps: number;
  /** Oldest first. */
  readonly progress: readonly EnrollmentProgress[];
  readonly enrolledBy?: string;
  readonly enrolledAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface EnrollmentsFilter {
  readonly program?: string;
  readonly subject?: SubjectRef;
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
   * cancelled one starts again with its completed steps.
   */
  enroll(program: string, subject: SubjectRef): AsyncResult<Enrollment>;
  /** A subject's enrollment in a program, or `null`. */
  enrollment(
    program: string,
    subject: SubjectRef,
  ): AsyncResult<Enrollment | null>;
  /**
   * The organization's enrollments, most recently changed first. Without
   * `enrollments.read`, the caller's own.
   */
  list(filter?: EnrollmentsFilter): AsyncResult<readonly Enrollment[]>;
  /** Marks a step done; completing the last step completes the enrollment. */
  complete(enrollmentId: string, step: string): AsyncResult<Enrollment>;
  /** Marks a step not done again. */
  reset(enrollmentId: string, step: string): AsyncResult<Enrollment>;
  /** Cancels an active enrollment; its completed steps stay. */
  cancel(enrollmentId: string): AsyncResult<Enrollment>;
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

function stepOf(value: unknown, fn: string): EnrollmentStep {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    ...optional("title", optionalText(row["title"])),
    ...optional("description", optionalText(row["description"])),
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
    enrolledAt: requiredInstant(row["enrolledAt"], "enrolledAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("organizationId", optionalText(row["organizationId"])),
    ...optional(
      "programVersion",
      typeof version === "number" ? version : undefined,
    ),
    ...optional("enrolledBy", optionalText(row["enrolledBy"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("cancelledAt", optionalInstant(row["cancelledAt"])),
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
    enroll: (program, subject) =>
      tenant().andThen((organizationId) =>
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
      ),
    enrollment: (program, subject) =>
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
    complete: (enrollmentId, step) =>
      call(
        "complete_enrollment_step",
        { enrollment_id: enrollmentId, step },
        one("complete_enrollment_step"),
      ),
    reset: (enrollmentId, step) =>
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
  };

  return withBlockHooks(client, options.hooks, {
    block: "enrollments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
