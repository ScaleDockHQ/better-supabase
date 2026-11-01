import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
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
  saveJob(input: {
    organizationId: string;
    job: JobInput<F>;
  }): AsyncResult<Job<F>>;
  /** Adds a candidate to an open job; applying again returns the same one. */
  apply(
    input: { jobId: string; candidate: Candidate | { readonly id: string } } & {
      readonly source?: string;
      readonly ownerId?: string;
      /** With `options.applicationExtraColumns`: values for those columns. */
      readonly fields?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<Application>;
  /** Moves it to the job pipeline's Hired stage; `application.hired` follows. */
  hire(applicationId: string): AsyncResult<Application>;
  reject(input: {
    applicationId: string;
    reason?: string | undefined;
  }): AsyncResult<Application>;
  withdraw(applicationId: string): AsyncResult<Application>;
  /** The caller's scorecard at the application's current stage. */
  score(input: {
    applicationId: string;
    card: {
      readonly rating: number;
      readonly recommendation?: Recommendation;
      readonly notes?: string;
      readonly scores?: readonly ScorecardScore[];
    };
  }): AsyncResult<Scorecard>;
  scheduleInterview(input: {
    applicationId: string;
    interview: {
      readonly startsAt: Temporal.Instant;
      readonly endsAt: Temporal.Instant;
      readonly interviewerIds?: readonly string[];
      readonly kind?: string;
      readonly location?: string;
    };
  }): AsyncResult<Interview>;
  detail(applicationId: string): AsyncResult<ApplicationDetail>;
  /** The organization's jobs, newest first; `status` keeps one status. */
  jobs(input: {
    organizationId: string;
    status?: JobStatus | undefined;
  }): AsyncResult<Job<F>[]>;
  /** A job's applications in board order; `state` keeps one state. */
  applications(input: {
    jobId: string;
    state?: ApplicationState | undefined;
  }): AsyncResult<Application[]>;
  /**
   * A job's applications grouped by stage, in board order. A stage's name and
   * order come from the pipelines block; this groups by `stageId` only.
   */
  pipeline(input: {
    jobId: string;
    state?: ApplicationState | undefined;
  }): AsyncResult<JobPipelineStage[]>;
  /**
   * One job and its applications grouped by stage, read together. A job the
   * caller can't see is `not_found`.
   */
  board(input: {
    organizationId: string;
    jobId: string;
    state?: ApplicationState | undefined;
  }): AsyncResult<JobBoard<F>>;
  /**
   * Closes the job: `saveJob` with `status: "closed"`, which stamps `closedAt`
   * and emits `job_opening.closed`. Closing a closed job changes nothing.
   */
  close(input: { organizationId: string; jobId: string }): AsyncResult<Job<F>>;
}

/** One stage's applications in `Hiring.pipeline`. */
export interface JobBoard<F extends object = Record<never, never>> {
  readonly job: Job<F>;
  readonly stages: readonly JobPipelineStage[];
}

export interface JobPipelineStage {
  /** `undefined` for applications that have no stage yet. */
  readonly stageId: string | undefined;
  readonly applications: readonly Application[];
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

  const readJob = (saved: Job): AsyncResult<Job<F>> =>
    AsyncResult.from(() => fields.read(saved.fields)).map((value) => ({
      ...saved,
      fields: value,
    }));

  const client: Hiring<F> = {
    saveJob: ({ organizationId, job }) => {
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
        .andThen(readJob);
    },
    apply: ({ jobId, candidate, ...apply }) =>
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
    reject: ({ applicationId, reason }) =>
      close(applicationId, "rejected", reason),
    withdraw: (applicationId) => close(applicationId, "withdrawn"),
    score: ({ applicationId, card }) =>
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
    scheduleInterview: ({ applicationId, interview }) =>
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
    jobs: ({ organizationId, status }) =>
      call(
        "list_jobs",
        { tenant: organizationId, status: status ?? null },
        (value) => recordsOf(value, "jobs").map(jobOf),
      ).andThen(async (jobs) => {
        const read: Job<F>[] = [];

        for (const job of jobs) {
          const result = await readJob(job);

          if (!result.ok) {
            return result;
          }

          read.push(result.data);
        }

        return ok(read);
      }),
    applications: ({ jobId, state }) =>
      call("list_applications", { job: jobId, state: state ?? null }, (value) =>
        recordsOf(value, "applications").map(applicationOf),
      ),
    pipeline: ({ jobId, state }) =>
      hooked.applications({ jobId, state }).map((applications) => {
        const stages = new Map<string | undefined, Application[]>();

        for (const application of applications) {
          const group = stages.get(application.stageId) ?? [];

          group.push(application);
          stages.set(application.stageId, group);
        }

        return [...stages].map(([stageId, grouped]) => ({
          stageId,
          applications: grouped,
        }));
      }),
    board: ({ organizationId, jobId, state }) =>
      AsyncResult.from<JobBoard<F>>(async () => {
        const [jobs, stages] = await Promise.all([
          hooked.jobs({ organizationId }),
          hooked.pipeline({ jobId, state }),
        ]);

        if (!jobs.ok) {
          return err(jobs.error);
        }

        if (!stages.ok) {
          return err(stages.error);
        }

        const found = jobs.data.find((job) => job.id === jobId);

        return found
          ? ok({ job: found, stages: stages.data })
          : err(dbError("not_found", "The job does not exist."));
      }),
    close: ({ organizationId, jobId }) =>
      hooked.saveJob({ organizationId, job: { id: jobId, status: "closed" } }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Hiring<F> = withBlockHooks(client, options.hooks, {
    block: "hiring",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
