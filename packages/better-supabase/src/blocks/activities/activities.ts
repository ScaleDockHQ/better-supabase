import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { AiFiles } from "../ai-files/types.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  EngagementNotes,
  EngagementNotesInput,
  EngagementRecording,
  NoteTaker,
  Transcriber,
  Transcript,
  TranscriptSegment,
} from "./recordings.ts";

import { blockFields } from "../../core/block-fields.ts";
import { injectableOf } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  errorText,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import {
  notesArg,
  notesOf,
  recordingOf,
  segmentOf,
  segmentsArg,
  transcriptOf,
} from "./recordings.ts";

/** A record an engagement is on. */
export interface EngagementSubject {
  readonly type: string;
  readonly id: string;
}

/** A call, email, meeting, note or task logged on one or more records. */
export interface Engagement<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** `call`, `email`, `meeting`, `note`, `task` or a configured type. */
  readonly type: string;
  readonly title: string;
  readonly body?: string;
  /** How it went, such as `connected`, `no_answer` or `replied`. */
  readonly outcome?: string;
  readonly ownerId?: string;
  readonly dueAt?: Temporal.Instant;
  readonly doneAt?: Temporal.Instant;
  readonly durationSeconds?: number;
  /** The id in the system it came from, such as a mail or calendar provider. */
  readonly externalRef?: string;
  /** The records it is on; the first is its main record. */
  readonly subjects: readonly EngagementSubject[];
  /** Open and past its due time. */
  readonly overdue: boolean;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
}

/**
 * The fields of a write. On update, left out keeps the value and `null` clears
 * it.
 */
export interface EngagementInput<F extends object = Record<never, never>> {
  readonly type?: string;
  readonly title?: string;
  readonly body?: string | null;
  readonly outcome?: string | null;
  /** Defaults to the caller on `log`. */
  readonly ownerId?: string | null;
  readonly dueAt?: Temporal.Instant | null;
  readonly doneAt?: Temporal.Instant | null;
  readonly durationSeconds?: number | null;
  /** Logging the same `externalRef` again updates the engagement. */
  readonly externalRef?: string | null;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** `F` types the engagements' extra columns, from the `fields` schema. */
export interface Activities<F extends object = Record<never, never>> {
  /**
   * Logs an engagement on the records in `subjects`, the first being its main
   * record.
   */
  log(
    organizationId: string,
    input: EngagementInput<F> & {
      readonly type: string;
      readonly title: string;
    },
    subjects: readonly EngagementSubject[],
  ): AsyncResult<Engagement<F>>;
  /** Changes an engagement, and its records when `subjects` is given. */
  update(
    id: string,
    input: EngagementInput<F>,
    subjects?: readonly EngagementSubject[],
  ): AsyncResult<Engagement<F>>;
  /** Marks it done now, with an outcome, or open again with `done: false`. */
  complete(
    id: string,
    options?: { readonly done?: boolean; readonly outcome?: string },
  ): AsyncResult<Engagement<F>>;
  remove(id: string): AsyncResult<boolean>;
  /** A record's engagements, newest first (50 by default, at most 200). */
  of(
    subject: EngagementSubject,
    options?: {
      readonly types?: readonly string[];
      readonly before?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement<F>[]>;
  /** The next open engagement with a due time on a record, or `undefined`. */
  next(subject: EngagementSubject): AsyncResult<Engagement<F> | undefined>;
  /** A member's open engagements, earliest due first. Default: the caller's. */
  open(
    organizationId: string,
    options?: {
      readonly ownerId?: string;
      readonly dueBefore?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement<F>[]>;
  /**
   * Attaches a ready ai-files file as a call or meeting recording
   * (`options.recordings`). With the jobs block it queues a transcription on
   * `engagements.transcribe`.
   */
  attachRecording(
    engagementId: string,
    fileId: string,
    options?: { readonly language?: string },
  ): AsyncResult<EngagementRecording>;
  /** An engagement's recordings, oldest first. */
  recordings(engagementId: string): AsyncResult<EngagementRecording[]>;
  /** A recording's speaker turns in order (500 by default, at most 5000). */
  transcript(
    recordingId: string,
    options?: { readonly after?: number; readonly limit?: number },
  ): AsyncResult<TranscriptSegment[]>;
  /** Replaces a recording's transcript, from a transcriber or an import. */
  saveTranscript(
    recordingId: string,
    transcript: Transcript & { readonly model?: string },
  ): AsyncResult<EngagementRecording>;
  /**
   * Transcribes a recording with `transcriber`, reading the file through
   * `files`, and saves the result. Runs on `service` when given.
   */
  transcribe(
    recordingId: string,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<EngagementRecording>;
  /**
   * The handler for the `engagements.transcribe` queue. The last attempt marks
   * the recording failed with the error.
   */
  transcribeJob(): JobHandler<{ readonly recordingId: string }>;
  /**
   * Transcribes pending recordings without a queue (service role). Returns how
   * many succeeded; a failure marks its recording failed.
   */
  drainRecordings(options?: {
    readonly batch?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<number>;
  /** The engagement's notes, or `undefined`. */
  notes(engagementId: string): AsyncResult<EngagementNotes | undefined>;
  /** Saves notes a member wrote, replacing earlier ones. */
  saveNotes(
    engagementId: string,
    notes: EngagementNotesInput,
  ): AsyncResult<EngagementNotes>;
  /**
   * Writes the engagement's notes with `noteTaker` from its transcripts and
   * saves them.
   */
  summarize(
    engagementId: string,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<EngagementNotes>;
}

export interface ActivitiesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the engagements' extra columns
   * (`blocks.activities.options.extraColumns`), keyed by column name. It types
   * and parses `fields` on reads and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Activities<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
  /** Calls as the service role, for `transcribe`, its job and the drain. */
  readonly service?: BlockTransport;
  /** The ai-files block, which `transcribe` reads recordings through. */
  readonly files?: AiFiles;
  /** Turns recordings into transcripts, for `transcribe`. */
  readonly transcriber?: Transcriber;
  /** Writes notes from transcripts, for `summarize`. */
  readonly noteTaker?: NoteTaker;
}

const missing = <T>(what: string, hint: string): AsyncResult<T> =>
  AsyncResult.err(
    dbError("invalid_request", `createActivities has no ${what}`, { hint }),
  );

/** Runs a transcriber or note taker, its throw as an `unexpected` error. */
const provider = <T>(hint: string, run: () => Promise<T>): AsyncResult<T> =>
  AsyncResult.from(async () => {
    try {
      return ok(await run());
    } catch (cause) {
      return err(dbError("unexpected", errorText(cause), { hint }));
    }
  });

function engagementOf(value: unknown): Engagement {
  const row = recordOf(value, "engagement");

  const optional = {
    body: optionalText(row["body"]),
    outcome: optionalText(row["outcome"]),
    ownerId: optionalText(row["owner_user_id"]),
    dueAt: optionalInstant(row["due_at"]),
    doneAt: optionalInstant(row["done_at"]),
    durationSeconds:
      typeof row["duration_seconds"] === "number"
        ? row["duration_seconds"]
        : undefined,
    externalRef: optionalText(row["external_ref"]),
    createdBy: optionalText(row["created_by"]),
  };

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    type: textOf(row["type"]),
    title: textOf(row["title"]),
    subjects: recordsOf(row["subjects"], "engagement subjects").map(
      (subject) => ({
        type: textOf(subject["type"]),
        id: textOf(subject["id"]),
      }),
    ),
    overdue: row["overdue"] === true,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...Object.fromEntries(
      Object.entries(optional).filter(([, value]) => value !== undefined),
    ),
  };
}

/** The attrs of a write: the keys the input sets, instants as ISO text. */
function attrsOf(input: EngagementInput): Record<string, unknown> {
  const { dueAt, doneAt, ...rest } = input;

  return {
    ...rest,
    ...(dueAt === undefined ? {} : { dueAt: instantArg(dueAt) ?? null }),
    ...(doneAt === undefined ? {} : { doneAt: instantArg(doneAt) ?? null }),
  };
}

const subjectsArg = (
  subjects: readonly EngagementSubject[],
): { type: string; id: string }[] =>
  subjects.map((subject) => ({ type: subject.type, id: subject.id }));

/**
 * The engagements block: calls, emails, meetings, notes and tasks on any record
 * registered in `config.subjects`, for a record's activity panel, a "next step"
 * and a member's task list.
 */
export function createActivities<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ActivitiesOptions<S>): Activities<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const transcriber = injectableOf("transcriber", options.transcriber);
  const noteTaker = injectableOf("note taker", options.noteTaker);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "engagement fields",
  );

  const parsed = (engagement: Engagement): AsyncResult<Engagement<F>> =>
    AsyncResult.from(() => fields.read(engagement.fields)).map((value) => ({
      ...engagement,
      fields: value,
    }));

  const parsedAll = (
    engagements: readonly Engagement[],
  ): AsyncResult<Engagement<F>[]> =>
    AsyncResult.from(async () => {
      const out: Engagement<F>[] = [];

      for (const engagement of engagements) {
        const read = await parsed(engagement);

        if (!read.ok) {
          return read;
        }

        out.push(read.data);
      }

      return ok(out);
    });

  /** The attrs of a write, with the extra fields checked first. */
  const checked = (
    input: EngagementInput<F>,
  ): AsyncResult<Record<string, unknown>> => {
    const { fields: extra, ...rest } = input;

    if (extra === undefined) {
      return AsyncResult.ok(attrsOf(rest));
    }

    return AsyncResult.from(() => fields.write({ ...extra })).map((valid) => ({
      ...attrsOf(rest),
      fields: valid,
    }));
  };

  const saveTranscript: Activities<F>["saveTranscript"] = (
    recordingId,
    transcript,
  ) =>
    service(
      "save_engagement_transcript",
      {
        recording: recordingId,
        segments: segmentsArg(transcript.segments),
        attrs: {
          language: transcript.language ?? null,
          durationSeconds: transcript.durationSeconds ?? null,
          model: transcript.model ?? null,
        },
      },
      recordingOf,
    );

  const transcribe: Activities<F>["transcribe"] = (
    recordingId,
    transcribeOptions = {},
  ) => {
    const { files } = options;

    if (transcriber === undefined) {
      return missing("transcriber", "ENGAGEMENT_NO_TRANSCRIBER");
    }

    if (files === undefined) {
      return missing("files block", "ENGAGEMENT_NO_FILES");
    }

    return service(
      "get_engagement_recording",
      { recording: recordingId },
      (value) => (value === null ? undefined : recordingOf(value)),
    )
      .andThen((recording) =>
        recording === undefined
          ? AsyncResult.err(
              dbError("not_found", "no such recording", {
                hint: "ENGAGEMENT_RECORDING_NOT_FOUND",
              }),
            )
          : files.files
              .sign(recording.fileId)
              .map((url) => ({ recording, url })),
      )
      .andThen(({ recording, url }) =>
        provider("ENGAGEMENT_TRANSCRIBE_FAILED", () =>
          transcriber.transcribe(
            {
              file: {
                id: recording.fileId,
                filename: recording.filename,
                mediaType: recording.mediaType,
              },
              url,
              read: () =>
                files.files
                  .read(recording.fileId)
                  .map(({ data }) => data)
                  .orThrow(),
              ...(recording.language === undefined
                ? {}
                : { language: recording.language }),
            },
            transcribeOptions.signal === undefined
              ? {}
              : { signal: transcribeOptions.signal },
          ),
        ),
      )
      .andThen((transcript) =>
        saveTranscript(recordingId, {
          ...transcript,
          model: transcriber.model,
        }),
      );
  };

  const fail = (recordingId: string, error: string) =>
    service(
      "fail_engagement_recording",
      { recording: recordingId, error },
      (value) => value === true,
    );

  const client: Activities<F> = {
    log: (organizationId, input, subjects) =>
      checked(input)
        .andThen((attrs) =>
          call(
            "log_engagement",
            { tenant: organizationId, attrs, subjects: subjectsArg(subjects) },
            engagementOf,
          ),
        )
        .andThen(parsed),
    update: (id, input, subjects) =>
      checked(input)
        .andThen((attrs) =>
          call(
            "update_engagement",
            {
              engagement: id,
              attrs,
              subjects: subjects === undefined ? null : subjectsArg(subjects),
            },
            engagementOf,
          ),
        )
        .andThen(parsed),
    complete: (id, complete = {}) =>
      call(
        "complete_engagement",
        {
          engagement: id,
          done: complete.done ?? true,
          outcome: complete.outcome ?? null,
        },
        engagementOf,
      ).andThen(parsed),
    remove: (id) =>
      call("delete_engagement", { engagement: id }, (value) => value === true),
    of: (subject, list = {}) =>
      call(
        "engagements_of",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          types: list.types === undefined ? null : [...list.types],
          before: instantArg(list.before) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "engagements_of").map(engagementOf),
      ).andThen(parsedAll),
    next: (subject) =>
      call(
        "next_engagement",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => (value === null ? undefined : engagementOf(value)),
      ).andThen((found) =>
        found === undefined ? AsyncResult.ok(undefined) : parsed(found),
      ),
    open: (organizationId, list = {}) =>
      call(
        "open_engagements",
        {
          tenant: organizationId,
          owner: list.ownerId ?? null,
          due_before: instantArg(list.dueBefore) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "open_engagements").map(engagementOf),
      ).andThen(parsedAll),
    attachRecording: (engagementId, fileId, attach = {}) =>
      call(
        "attach_engagement_recording",
        {
          engagement: engagementId,
          file: fileId,
          language: attach.language ?? null,
        },
        recordingOf,
      ),
    recordings: (engagementId) =>
      call("engagement_recordings", { engagement: engagementId }, (value) =>
        recordsOf(value, "engagement_recordings").map(recordingOf),
      ),
    transcript: (recordingId, page = {}) =>
      call(
        "engagement_transcript",
        {
          recording: recordingId,
          after: page.after ?? null,
          page_size: page.limit ?? null,
        },
        (value) => recordsOf(value, "engagement_transcript").map(segmentOf),
      ),
    saveTranscript,
    transcribe,
    transcribeJob: () => async (payload, job, signal) => {
      const result = await transcribe(payload.recordingId, { signal });

      if (result.ok) {
        return;
      }

      if (job.attempts >= job.maxAttempts) {
        await fail(payload.recordingId, result.error.message);
      }

      throw new DbException(result.error);
    },
    drainRecordings: (drain = {}) =>
      service(
        "pending_engagement_recordings",
        { batch: drain.batch ?? null },
        (value) => (Array.isArray(value) ? value.map(textOf) : []),
      ).andThen((ids) =>
        AsyncResult.from(async () => {
          let done = 0;

          for (const id of ids) {
            if (drain.signal?.aborted) {
              break;
            }

            const result = await transcribe(
              id,
              drain.signal === undefined ? {} : { signal: drain.signal },
            );

            if (result.ok) {
              done += 1;
            } else {
              await fail(id, result.error.message);
            }
          }

          return ok(done);
        }),
      ),
    notes: (engagementId) =>
      call("engagement_notes", { engagement: engagementId }, (value) =>
        value === null ? undefined : notesOf(value),
      ),
    saveNotes: (engagementId, notes) =>
      call(
        "save_engagement_notes",
        {
          engagement: engagementId,
          notes: notesArg(notes, "member", undefined),
        },
        notesOf,
      ),
    summarize: (engagementId, summarizeOptions = {}) => {
      if (noteTaker === undefined) {
        return missing("note taker", "ENGAGEMENT_NO_NOTE_TAKER");
      }

      return call(
        "engagement_with_transcripts",
        { engagement: engagementId },
        (value) => value,
      )
        .andThen((value) =>
          value === null
            ? AsyncResult.err(
                dbError("not_found", "no such engagement", {
                  hint: "ENGAGEMENT_NOT_FOUND",
                }),
              )
            : parsed(
                engagementOf(recordOf(value, "engagement")["engagement"]),
              ).map((engagement) => ({
                engagement,
                transcript: transcriptOf(
                  recordOf(value, "engagement")["segments"],
                ),
              })),
        )
        .andThen((input) =>
          provider("ENGAGEMENT_SUMMARIZE_FAILED", () =>
            noteTaker.summarize(
              input,
              summarizeOptions.signal === undefined
                ? {}
                : { signal: summarizeOptions.signal },
            ),
          ),
        )
        .andThen((notes) =>
          call(
            "save_engagement_notes",
            {
              engagement: engagementId,
              notes: notesArg(notes, "ai", noteTaker.model),
            },
            notesOf,
          ),
        );
    },
  };

  return withBlockHooks(client, options.hooks, {
    block: "activities",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
