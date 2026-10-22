import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type { MailSendDraft } from "../mail-sync/mail-sync.ts";
import type { BlockPorts } from "../ports.ts";
import type { BlockOptions, RecordRef } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  errorText,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

const SEQUENCE_STATUSES = ["draft", "active", "paused", "archived"] as const;
const RUN_STATUSES = ["active", "paused", "completed", "exited"] as const;
const EXIT_REASONS = ["replied", "manual", "failed", "archived"] as const;

/** Only an active sequence takes enrollments and runs its steps. */
export type SequenceStatus = (typeof SEQUENCE_STATUSES)[number];

/** Where a recipient's run stands. */
export type SequenceEnrollmentStatus = (typeof RUN_STATUSES)[number];

/** Why a run exited. */
export type SequenceExitReason = (typeof EXIT_REASONS)[number];

/**
 * Sends an email from the recipient's mailbox. `subject`, `text` and `html`
 * take `{{key}}` placeholders, filled from the enrollment's variables
 * (HTML-escaped in `html`). After the first email, the rest reply on its
 * thread.
 */
export interface SequenceEmailStep {
  readonly id: string;
  readonly kind: "email";
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
  /** The `templates` version the email was written from. */
  readonly templateVersionId?: string;
  /** Tracks opens and clicks when mail-sync tracking is on. Default true. */
  readonly track?: boolean;
}

/** Creates a work item for whoever enrolled the recipient. */
export interface SequenceTaskStep {
  readonly id: string;
  readonly kind: "task";
  readonly title: string;
  readonly body?: string;
  /** Minutes until the work item is due. */
  readonly dueInMinutes?: number;
}

/** Waits before the next step. */
export interface SequenceWaitStep {
  readonly id: string;
  readonly kind: "wait";
  /** 1 to 525600 (a year). */
  readonly minutes: number;
}

/** One step of a sequence; its id is a step of the enrollment program. */
export type SequenceStep =
  | SequenceEmailStep
  | SequenceTaskStep
  | SequenceWaitStep;

/** How many recipients are in each state. */
export interface SequenceCounts {
  readonly active: number;
  readonly paused: number;
  readonly completed: number;
  readonly exited: number;
  /** Of the exited, how many replied. */
  readonly replied: number;
}

export interface Sequence {
  readonly id: string;
  readonly organizationId: string;
  /** Unique in the organization. */
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly status: SequenceStatus;
  /** Whether a reply ends the recipient's run. */
  readonly exitOnReply: boolean;
  /** The mailbox email steps send from when the enrollment names none. */
  readonly accountId?: string;
  readonly steps: readonly SequenceStep[];
  /** Raised each time the steps change. */
  readonly version: number;
  readonly counts: SequenceCounts;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `upsert` takes; keys left out keep their value. */
export interface SequenceInput {
  readonly id?: string;
  readonly key?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly status?: SequenceStatus;
  readonly exitOnReply?: boolean;
  readonly accountId?: string | null;
  readonly steps?: readonly SequenceStep[];
}

/** A recipient's run through a sequence. `id` is the enrollment. */
export interface SequenceEnrollment {
  readonly id: string;
  readonly organizationId: string;
  readonly sequenceId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly address?: string;
  readonly name?: string;
  readonly accountId?: string;
  /** The thread the first email started. */
  readonly threadId?: string;
  /** The step that runs next, absent once the run ended. */
  readonly step?: string;
  readonly nextRunAt?: Temporal.Instant;
  readonly status: SequenceEnrollmentStatus;
  readonly exitReason?: SequenceExitReason;
  /** Send attempts of the current email step. */
  readonly attempts: number;
  readonly lastError?: string;
  readonly variables: Readonly<Record<string, unknown>>;
  readonly enrolledBy?: string;
  /** The ids of the steps done, in the order they finished. */
  readonly completedSteps: readonly string[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `enroll` takes. */
export interface SequenceEnrollInput {
  /** The recipient's address; a person's email when left out. */
  readonly address?: string;
  readonly name?: string;
  /** The mailbox to send from; the sequence's, then the caller's, by default. */
  readonly accountId?: string;
  /** Values for the `{{key}}` placeholders. */
  readonly variables?: Readonly<
    Record<string, string | number | boolean | null>
  >;
}

/** What `enrollments` filters on. */
export interface SequenceEnrollmentsFilter {
  readonly sequenceId?: string;
  readonly subject?: RecordRef;
  readonly status?: SequenceEnrollmentStatus;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  /** The `createdAt` of the last row of the previous page. */
  readonly before?: Temporal.Instant;
}

/** What one `runDue` call did. */
export interface SequenceRunReport {
  /** Wait and task steps finished. */
  readonly ran: number;
  /** Email steps sent. */
  readonly sent: number;
  /** Email steps that failed to send; they run again later. */
  readonly failed: number;
}

export interface Sequences {
  upsert(input: SequenceInput): AsyncResult<Sequence>;
  /** The organization's sequences; archived ones only with that status. */
  list(filter?: {
    readonly status?: SequenceStatus;
  }): AsyncResult<readonly Sequence[]>;
  get(sequenceId: string): AsyncResult<Sequence>;
  /** Deletes a sequence with its enrollments; false when there was none. */
  delete(sequenceId: string): AsyncResult<boolean>;
  /**
   * Enrolls a record in an active sequence. Enrolling a record already running
   * returns its run; a finished or exited run starts over.
   */
  enroll(
    sequenceId: string,
    subject: RecordRef,
    input?: SequenceEnrollInput,
  ): AsyncResult<SequenceEnrollment>;
  pause(enrollmentId: string): AsyncResult<SequenceEnrollment>;
  resume(enrollmentId: string): AsyncResult<SequenceEnrollment>;
  /** Ends a run by hand; its completed steps stay. */
  exit(enrollmentId: string): AsyncResult<SequenceEnrollment>;
  enrollments(
    filter?: SequenceEnrollmentsFilter,
  ): AsyncResult<readonly SequenceEnrollment[]>;
  /**
   * Runs the due steps as the service role and sends the due emails through the
   * `mailer` port. Call it from a cron route or a job every few minutes.
   */
  runDue(options?: { readonly limit?: number }): AsyncResult<SequenceRunReport>;
}

export interface SequencesOptions extends BlockOptions {
  /** Sends email steps: the `mail-sync` block, which `createBlocks` passes. */
  readonly mailer?: BlockPorts["mailer"];
  readonly hooks?: NoInfer<BlockHooks<Sequences>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

interface EmailClaim {
  readonly enrollmentId: string;
  readonly accountId?: string;
  readonly threadId?: string;
  readonly to: { readonly address: string; readonly name?: string };
  readonly step: SequenceEmailStep;
  readonly variables: Readonly<Record<string, unknown>>;
}

const PLACEHOLDER = /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/g;

const HTML_ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

const escapeHtml = (value: string): string =>
  value.replaceAll(/[&<>"']/g, (char) => HTML_ESCAPES[char] ?? char);

/**
 * `template` with each `{{key}}` replaced by `variables[key]`; an unknown key
 * becomes empty. `html` escapes the values.
 */
export function fillPlaceholders(
  template: string,
  variables: Readonly<Record<string, unknown>>,
  html = false,
): string {
  return template.replaceAll(PLACEHOLDER, (_, key: string) => {
    const value = variables[key];

    const text =
      value === null || value === undefined || typeof value === "object"
        ? ""
        : String(value);

    return html ? escapeHtml(text) : text;
  });
}

function stepOf(value: unknown): SequenceStep {
  const row = recordOf(value, "sequence step");
  const id = textOf(row["id"]);

  switch (row["kind"]) {
    case "email": {
      return {
        id,
        kind: "email",
        subject: textOf(row["subject"]),
        ...(typeof row["text"] === "string" ? { text: row["text"] } : {}),
        ...(typeof row["html"] === "string" ? { html: row["html"] } : {}),
        ...(typeof row["templateVersionId"] === "string"
          ? { templateVersionId: row["templateVersionId"] }
          : {}),
        ...(typeof row["track"] === "boolean" ? { track: row["track"] } : {}),
      };
    }

    case "task": {
      return {
        id,
        kind: "task",
        title: textOf(row["title"]),
        ...(typeof row["body"] === "string" ? { body: row["body"] } : {}),
        ...(typeof row["dueInMinutes"] === "number"
          ? { dueInMinutes: row["dueInMinutes"] }
          : {}),
      };
    }

    default: {
      return { id, kind: "wait", minutes: Number(row["minutes"] ?? 0) };
    }
  }
}

function countsOf(value: unknown): SequenceCounts {
  const row = isRecord(value) ? value : {};
  const count = (key: string): number => Number(row[key] ?? 0);

  return {
    active: count("active"),
    paused: count("paused"),
    completed: count("completed"),
    exited: count("exited"),
    replied: count("replied"),
  };
}

function sequenceOf(value: unknown, fn: string): Sequence {
  const row = recordOf(value, fn);
  const description = optionalText(row["description"]);
  const accountId = optionalText(row["accountId"]);
  const createdBy = optionalText(row["createdBy"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    status: enumOrThrow(row["status"], SEQUENCE_STATUSES, "sequence status"),
    exitOnReply: row["exitOnReply"] !== false,
    steps: recordsOf(row["steps"], fn).map(stepOf),
    version: Number(row["version"] ?? 1),
    counts: countsOf(row["counts"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...(description === undefined ? {} : { description }),
    ...(accountId === undefined ? {} : { accountId }),
    ...(createdBy === undefined ? {} : { createdBy }),
  };
}

function enrollmentOf(value: unknown, fn: string): SequenceEnrollment {
  const row = recordOf(value, fn);

  const optional = (key: string): Record<string, string> => {
    const text = optionalText(row[key]);

    return text === undefined ? {} : { [key]: text };
  };

  const nextRunAt = optionalInstant(row["nextRunAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    sequenceId: textOf(row["sequenceId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    status: enumOrThrow(
      row["status"],
      RUN_STATUSES,
      "sequence enrollment status",
    ),
    attempts: Number(row["attempts"] ?? 0),
    variables: isRecord(row["variables"]) ? row["variables"] : {},
    completedSteps: stringsOf(row["completedSteps"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("address"),
    ...optional("name"),
    ...optional("accountId"),
    ...optional("threadId"),
    ...optional("step"),
    ...optional("lastError"),
    ...optional("enrolledBy"),
    ...(row["exitReason"] === null || row["exitReason"] === undefined
      ? {}
      : {
          exitReason: enumOrThrow(
            row["exitReason"],
            EXIT_REASONS,
            "exit reason",
          ),
        }),
    ...(nextRunAt === undefined ? {} : { nextRunAt }),
  };
}

function claimsOf(value: unknown): {
  readonly ran: number;
  readonly emails: readonly EmailClaim[];
} {
  const row = recordOf(value, "run_due_sequences");

  return {
    ran: Number(row["ran"] ?? 0),
    emails: recordsOf(row["emails"], "run_due_sequences").map((claim) => {
      const to = recordOf(claim["to"], "run_due_sequences");
      const step = stepOf(claim["step"]);
      const accountId = optionalText(claim["accountId"]);
      const threadId = optionalText(claim["threadId"]);
      const name = optionalText(to["name"]);

      return {
        enrollmentId: textOf(claim["enrollmentId"]),
        to: {
          address: textOf(to["address"]),
          ...(name === undefined ? {} : { name }),
        },
        // SAFETY: run_due_sequences returns only email steps.
        step: step as SequenceEmailStep,
        variables: isRecord(claim["variables"]) ? claim["variables"] : {},
        ...(accountId === undefined ? {} : { accountId }),
        ...(threadId === undefined ? {} : { threadId }),
      };
    }),
  };
}

/** The draft one claimed email step sends, placeholders filled. */
export function sequenceDraft(claim: {
  readonly to: { readonly address: string; readonly name?: string };
  readonly threadId?: string;
  readonly step: SequenceEmailStep;
  readonly variables: Readonly<Record<string, unknown>>;
}): MailSendDraft {
  const { step, variables } = claim;

  return {
    to: [claim.to],
    subject: fillPlaceholders(step.subject, variables),
    ...(step.text === undefined
      ? {}
      : { text: fillPlaceholders(step.text, variables) }),
    ...(step.html === undefined
      ? {}
      : { html: fillPlaceholders(step.html, variables, true) }),
    ...(claim.threadId === undefined ? {} : { threadId: claim.threadId }),
    ...(step.templateVersionId === undefined
      ? {}
      : { templateVersionId: step.templateVersionId }),
    ...(step.track === undefined ? {} : { track: step.track }),
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

/**
 * Multi-step outreach sequences: email, task and wait steps that run per
 * recipient as an enrollment program, until a reply ends the run.
 */
export function createSequences(options: SequencesOptions): Sequences {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const enrollment = (fn: string) => (value: unknown) =>
    enrollmentOf(value, fn);

  const change = (enrollmentId: string, action: string) =>
    call(
      "change_sequence_enrollment",
      { enrollment_id: enrollmentId, action },
      enrollment("change_sequence_enrollment"),
    );

  const send = async (claim: EmailClaim): Promise<Result<string | null>> => {
    if (options.mailer === undefined) {
      return err(
        dbError(
          "unsupported",
          "no mailer: install mail-sync to send email steps",
          { hint: "SEQUENCE_NO_MAILER" },
        ),
      );
    }

    if (claim.accountId === undefined) {
      return err(
        dbError(
          "invalid_request",
          "the enrollment has no mailbox to send from",
          { hint: "SEQUENCE_NO_MAILBOX" },
        ),
      );
    }

    const sent = await options.mailer.send(
      claim.accountId,
      sequenceDraft(claim),
    );

    return sent.ok ? ok(sent.data.id) : sent;
  };

  const client: Sequences = {
    upsert: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_sequence",
          { tenant: organizationId, sequence: definedOf(input) },
          (value) => sequenceOf(value, "save_sequence"),
        ),
      ),
    list: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_sequences",
          { tenant: organizationId, status: filter.status ?? null },
          (value) =>
            recordsOf(value, "list_sequences").map((row) =>
              sequenceOf(row, "list_sequences"),
            ),
        ),
      ),
    get: (sequenceId) =>
      call("get_sequence", { sequence_id: sequenceId }, (value) =>
        sequenceOf(value, "get_sequence"),
      ),
    delete: (sequenceId) =>
      call(
        "delete_sequence",
        { sequence_id: sequenceId },
        (value) => value === true,
      ),
    enroll: (sequenceId, subject, input = {}) =>
      call(
        "enroll_in_sequence",
        {
          sequence_id: sequenceId,
          subject_type: subject.type,
          subject_id: subject.id,
          attrs: definedOf(input),
        },
        enrollment("enroll_in_sequence"),
      ),
    pause: (enrollmentId) => change(enrollmentId, "pause"),
    resume: (enrollmentId) => change(enrollmentId, "resume"),
    exit: (enrollmentId) => change(enrollmentId, "exit"),
    enrollments: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_sequence_enrollments",
          {
            tenant: organizationId,
            filter: definedOf({
              sequence: filter.sequenceId,
              subjectType: filter.subject?.type,
              subjectId: filter.subject?.id,
              status: filter.status,
              limit: filter.limit,
              before: instantArg(filter.before),
            }),
          },
          (value) =>
            recordsOf(value, "list_sequence_enrollments").map(
              enrollment("list_sequence_enrollments"),
            ),
        ),
      ),
    runDue: (run = {}) =>
      service(
        "run_due_sequences",
        { max_count: run.limit ?? 50 },
        claimsOf,
      ).andThen(async (claims) => {
        let sent = 0;
        let failed = 0;

        for (const claim of claims.emails) {
          const outcome = await send(claim);

          const reported = await (outcome.ok
            ? service(
                "sequence_step_sent",
                {
                  enrollment_id: claim.enrollmentId,
                  step: claim.step.id,
                  message_id: outcome.data,
                },
                () => true,
              )
            : service(
                "sequence_step_failed",
                {
                  enrollment_id: claim.enrollmentId,
                  step: claim.step.id,
                  error: errorText(outcome.error),
                },
                () => true,
              ));

          if (!reported.ok) {
            return reported;
          }

          if (outcome.ok) {
            sent += 1;
          } else {
            failed += 1;
          }
        }

        return ok({ ran: claims.ran, sent, failed });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "sequences",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
