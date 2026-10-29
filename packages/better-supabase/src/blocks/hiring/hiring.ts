import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { compact, refOf } from "../sales-shared.ts";
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

export type JobStatus = "draft" | "open" | "closed";

export type ApplicationState = "active" | "hired" | "rejected" | "withdrawn";

export type Recommendation = "strong_no" | "no" | "yes" | "strong_yes";

const JOB_STATUSES: readonly JobStatus[] = ["draft", "open", "closed"];

const STATES: readonly ApplicationState[] = [
  "active",
  "hired",
  "rejected",
  "withdrawn",
];

const RECOMMENDATIONS: readonly Recommendation[] = [
  "strong_no",
  "no",
  "yes",
  "strong_yes",
];

/** A job. `F` types the extra columns the `fields` schema describes. */
export interface Job<F extends object = Record<never, never>> {
  readonly id: string;
  readonly title: string;
  readonly teamId?: string;
  readonly location?: string;
  readonly employmentType?: string;
  readonly description?: string;
  readonly hiringManagerId?: string;
  readonly status: JobStatus;
  readonly openedAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
}

export interface JobInput<F extends object = Record<never, never>> {
  readonly id?: string;
  readonly title?: string;
  readonly teamId?: string | null;
  readonly location?: string | null;
  readonly employmentType?: string | null;
  readonly description?: string | null;
  readonly hiringManagerId?: string | null;
  readonly status?: JobStatus;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** A candidate's record in `config.subjects`, a person by default. */
export interface Candidate {
  readonly type: string;
  readonly id: string;
}

export interface Application {
  readonly id: string;
  readonly jobId: string;
  readonly candidate: Candidate;
  readonly source?: string;
  /** The recruiter who owns it. */
  readonly ownerId?: string;
  readonly pipelineId?: string;
  readonly stageId?: string;
  readonly stageEnteredAt?: Temporal.Instant;
  readonly state: ApplicationState;
  readonly rejectionReason?: string;
  readonly hiredAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  /** With `options.applicationExtraColumns`: those columns, by name. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

export interface ScorecardScore {
  readonly criterion: string;
  readonly score: number;
  readonly notes?: string;
}

export interface Scorecard {
  readonly id: string;
  readonly stageId?: string;
  readonly reviewerId: string;
  /** 1 to 4. */
  readonly rating: number;
  readonly recommendation?: Recommendation;
  readonly notes?: string;
  readonly scores?: readonly ScorecardScore[];
  readonly submittedAt: Temporal.Instant;
}

export interface Interview {
  readonly id: string;
  readonly kind?: string;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
  readonly location?: string;
  readonly interviewerIds: readonly string[];
}

export interface ApplicationDetail extends Application {
  readonly scorecards: readonly Scorecard[];
  readonly interviews: readonly Interview[];
  readonly averageRating?: number;
}

/** `F` types the jobs' extra columns, from the `fields` schema. */
export interface Hiring<F extends object = Record<never, never>> {
  saveJob(organizationId: string, job: JobInput<F>): AsyncResult<Job<F>>;
  /** Adds a candidate to an open job; applying again returns the same one. */
  apply(
    jobId: string,
    candidate: Candidate | { readonly id: string },
    options?: {
      readonly source?: string;
      readonly ownerId?: string;
      /** With `options.applicationExtraColumns`: values for those columns. */
      readonly fields?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<Application>;
  /** Moves it to the job pipeline's Hired stage; `application.hired` follows. */
  hire(applicationId: string): AsyncResult<Application>;
  reject(applicationId: string, reason?: string): AsyncResult<Application>;
  withdraw(applicationId: string): AsyncResult<Application>;
  /** The caller's scorecard at the application's current stage. */
  score(
    applicationId: string,
    card: {
      readonly rating: number;
      readonly recommendation?: Recommendation;
      readonly notes?: string;
      readonly scores?: readonly ScorecardScore[];
    },
  ): AsyncResult<Scorecard>;
  scheduleInterview(
    applicationId: string,
    interview: {
      readonly startsAt: Temporal.Instant;
      readonly endsAt: Temporal.Instant;
      readonly interviewerIds?: readonly string[];
      readonly kind?: string;
      readonly location?: string;
    },
  ): AsyncResult<Interview>;
  detail(applicationId: string): AsyncResult<ApplicationDetail>;
}

export interface HiringOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the jobs' extra columns
   * (`blocks.hiring.options.extraColumns`), keyed by column name. It types and
   * parses `fields` on `saveJob` and validates the ones it writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Hiring<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function jobOf(value: unknown): Job {
  const row = recordOf(value, "job");

  return compact<Job>({
    id: textOf(row["id"]),
    title: textOf(row["title"]),
    teamId: optionalText(row["team_id"]),
    location: optionalText(row["location"]),
    employmentType: optionalText(row["employment_type"]),
    description: optionalText(row["description"]),
    hiringManagerId: optionalText(row["hiring_manager_user_id"]),
    status: enumOrThrow(row["status"], JOB_STATUSES, "job status"),
    openedAt: optionalInstant(row["opened_at"]),
    closedAt: optionalInstant(row["closed_at"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  });
}

function applicationOf(value: unknown): Application {
  const row = recordOf(value, "application");

  return compact<Application>({
    id: textOf(row["id"]),
    jobId: textOf(row["job_id"]),
    candidate: refOf(row["candidate_type"], row["candidate_id"]) ?? {
      type: "",
      id: "",
    },
    source: optionalText(row["source"]),
    ownerId: optionalText(row["owner_user_id"]),
    pipelineId: optionalText(row["pipeline_id"]),
    stageId: optionalText(row["stage_id"]),
    stageEnteredAt: optionalInstant(row["stage_entered_at"]),
    state: enumOrThrow(row["state"], STATES, "application state"),
    rejectionReason: optionalText(row["rejection_reason"]),
    hiredAt: optionalInstant(row["hired_at"]),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : undefined,
  });
}

function scoreOf(value: unknown): ScorecardScore {
  const row = recordOf(value, "score");

  return compact<ScorecardScore>({
    criterion: textOf(row["criterion"]),
    score: Number(row["score"]),
    notes: optionalText(row["notes"]),
  });
}

function scorecardOf(value: unknown): Scorecard {
  const row = recordOf(value, "scorecard");
  const recommendation = row["recommendation"];

  return compact<Scorecard>({
    id: textOf(row["id"]),
    stageId: optionalText(row["stage_id"]),
    reviewerId: textOf(row["reviewer_user_id"]),
    rating: Number(row["rating"]),
    recommendation:
      recommendation === null || recommendation === undefined
        ? undefined
        : enumOrThrow(recommendation, RECOMMENDATIONS, "recommendation"),
    notes: optionalText(row["notes"]),
    scores: Array.isArray(row["scores"])
      ? recordsOf(row["scores"], "scores").map(scoreOf)
      : undefined,
    submittedAt: requiredInstant(row["submitted_at"], "submittedAt"),
  });
}

function interviewOf(value: unknown): Interview {
  const row = recordOf(value, "interview");

  return compact<Interview>({
    id: textOf(row["id"]),
    kind: optionalText(row["kind"]),
    startsAt: requiredInstant(row["starts_at"], "startsAt"),
    endsAt: requiredInstant(row["ends_at"], "endsAt"),
    location: optionalText(row["location"]),
    interviewerIds: Array.isArray(row["interviewer_user_ids"])
      ? row["interviewer_user_ids"].map(String)
      : [],
  });
}

/**
 * The hiring block: jobs and applications on a pipeline per job, with
 * scorecards and interviews. Act on `application.hired` to create the employee
 * in your app.
 */
export function createHiring<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: HiringOptions<S>): Hiring<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "job fields");

  const close = (applicationId: string, outcome: string, reason?: string) =>
    call(
      "close_application",
      { application: applicationId, outcome, reason: reason ?? null },
      applicationOf,
    );

  const client: Hiring<F> = {
    saveJob: (organizationId, job) => {
      const { id, fields: extra, ...attrs } = job;

      return AsyncResult.from(() => fields.write({ ...extra }))
        .andThen((valid) =>
          call(
            "save_job",
            {
              tenant: organizationId,
              job: id ?? null,
              attrs: extra === undefined ? attrs : { ...attrs, fields: valid },
            },
            jobOf,
          ),
        )
        .andThen((saved) =>
          AsyncResult.from(() => fields.read(saved.fields)).map((value) => ({
            ...saved,
            fields: value,
          })),
        );
    },
    apply: (jobId, candidate, apply = {}) =>
      call(
        "apply_to_job",
        {
          job: jobId,
          candidate: { ...candidate },
          source: apply.source ?? null,
          owner: apply.ownerId ?? null,
          ...(apply.fields !== undefined && { fields: { ...apply.fields } }),
        },
        applicationOf,
      ),
    hire: (applicationId) => close(applicationId, "hired"),
    reject: (applicationId, reason) => close(applicationId, "rejected", reason),
    withdraw: (applicationId) => close(applicationId, "withdrawn"),
    score: (applicationId, card) =>
      call(
        "submit_scorecard",
        {
          application: applicationId,
          rating: card.rating,
          recommendation: card.recommendation ?? null,
          notes: card.notes ?? null,
          ...(card.scores !== undefined && {
            scores: card.scores.map((score) => ({ ...score })),
          }),
        },
        scorecardOf,
      ),
    scheduleInterview: (applicationId, interview) =>
      call(
        "schedule_interview",
        {
          application: applicationId,
          starts_at: instantArg(interview.startsAt),
          ends_at: instantArg(interview.endsAt),
          interviewers: [...(interview.interviewerIds ?? [])],
          kind: interview.kind ?? null,
          location: interview.location ?? null,
        },
        interviewOf,
      ),
    detail: (applicationId) =>
      call("application_detail", { application: applicationId }, (value) => {
        const row = recordOf(value, "application_detail");

        return compact<ApplicationDetail>({
          ...applicationOf(row),
          scorecards: recordsOf(row["scorecards"], "scorecards").map(
            scorecardOf,
          ),
          interviews: recordsOf(row["interviews"], "interviews").map(
            interviewOf,
          ),
          averageRating:
            row["averageRating"] === null || row["averageRating"] === undefined
              ? undefined
              : Number(row["averageRating"]),
        });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "hiring",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
