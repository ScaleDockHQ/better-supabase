import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  FormDefinition,
  FormJsonSchema,
} from "../../core/contracts/form-definition.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { FormScore } from "./scoring.ts";
import type { FormAnswers } from "./validate.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { isFormDefinition } from "../../core/contracts/form-definition.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface FormsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the forms' extra columns
   * (`blocks.forms.options.extraColumns`), keyed by column name. It types and
   * parses `fields` on reads and validates them on `create` and `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Forms<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type FormStatus = "draft" | "open" | "closed" | "archived";

export type FormSubmissionStatus =
  | "draft"
  | "submitted"
  | "accepted"
  | "rejected";

export type FormSubmissionSource = "member" | "public" | "service";

/** A form. `F` types the extra columns the `fields` schema describes. */
export interface Form<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly title: string;
  readonly description?: string;
  readonly status: FormStatus;
  readonly currentVersionId?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
}

/** One published definition and the JSON Schema generated from it. */
export interface FormVersion {
  readonly id: string;
  readonly formId: string;
  readonly number: number;
  /** The definition with its custom fields copied in. */
  readonly definition: FormDefinition;
  readonly schema: FormJsonSchema;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** A form with its current version, from `get`. */
export interface FormDetail<
  F extends object = Record<never, never>,
> extends Form<F> {
  readonly version?: FormVersion;
}

/** What `getPublic` shows a respondent who holds the link. */
export interface PublicForm {
  readonly id: string;
  readonly title: string;
  readonly description?: string;
  readonly version: Omit<FormVersion, "createdBy">;
}

export interface FormSubmission {
  readonly id: string;
  readonly organizationId: string;
  readonly formId: string;
  readonly versionId: string;
  /** The record the submission belongs to, or the one its handler created. */
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly respondentId?: string;
  readonly answers: FormAnswers;
  readonly status: FormSubmissionStatus;
  readonly source: FormSubmissionSource;
  readonly reviewedBy?: string;
  readonly reviewedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly submittedAt?: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /**
   * The grade Postgres gave a submission to a scored version; `undefined` for a
   * draft or a form without correct answers.
   */
  readonly score?: FormScore;
}

/** The NPS counts of one period, or of every answer. */
export interface NpsCounts {
  readonly responses: number;
  readonly promoters: number;
  readonly passives: number;
  readonly detractors: number;
  /** From -100 to 100, to one decimal; `undefined` without responses. */
  readonly score?: number;
}

export interface NpsPeriod extends NpsCounts {
  /** The period's first instant (UTC). */
  readonly start: Temporal.Instant;
}

/** `nps`: the counts over every answer, and per period with a `bucket`. */
export interface FormNps extends NpsCounts {
  /** The `nps` field the counts are for. */
  readonly field: string;
  readonly periods: readonly NpsPeriod[];
}

export type NpsBucket = "day" | "week" | "month" | "quarter" | "year";

export interface NpsOptions {
  /** Default: the current version's first `nps` field. */
  readonly field?: string;
  /** Submissions from this instant on. */
  readonly since?: Temporal.Instant;
  /** Submissions before this instant. */
  readonly until?: Temporal.Instant;
  /** Adds `periods`, by UTC day, week, month, quarter or year. */
  readonly bucket?: NpsBucket;
}

export interface PublicSubmission {
  readonly id: string;
  readonly status: FormSubmissionStatus;
  readonly submittedAt?: Temporal.Instant;
}

export interface FormInput<F extends object = Record<never, never>> {
  readonly organizationId: string;
  /** Unique in the organization; lowercase letters, digits, `_` and `-`. */
  readonly key: string;
  readonly title: string;
  readonly description?: string;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface FormUpdate<F extends object = Record<never, never>> {
  readonly title?: string;
  readonly description?: string;
  readonly status?: FormStatus;
  /**
   * Values for the extra columns, by column name; the ones left out keep their
   * value.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface SubmitOptions {
  /** Links the submission to a record, such as the deal it is about. */
  readonly subjectType?: string;
  readonly subjectId?: string;
  /** Continues the caller's draft. */
  readonly submissionId?: string;
  /** Saves without validating; submit again without `draft` to finish. */
  readonly draft?: boolean;
}

export interface PublicSubmitOptions {
  /**
   * Passed to the `before_public_form_submission` hook, such as a Turnstile
   * token.
   */
  readonly botToken?: string;
}

export interface SubmissionListOptions {
  /** Default: every status. */
  readonly status?: FormSubmissionStatus;
  readonly pageSize?: number;
  /** Submissions created before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

/** `F` types the forms' extra columns, from the `fields` schema. */
export interface Forms<F extends object = Record<never, never>> {
  create(input: FormInput<F>): AsyncResult<Form<F>>;
  update(id: string, update: FormUpdate<F>): AsyncResult<Form<F>>;
  /** Publishes a definition as the form's next version and makes it current. */
  publish(formId: string, definition: FormDefinition): AsyncResult<FormVersion>;
  get(id: string): AsyncResult<FormDetail<F>>;
  getVersion(versionId: string): AsyncResult<FormVersion>;
  list(
    organizationId: string,
    options?: { readonly status?: FormStatus },
  ): AsyncResult<readonly Form<F>[]>;
  /** Submits answers to the form's current version; Postgres validates them. */
  submit(
    formId: string,
    answers: FormAnswers,
    options?: SubmitOptions,
  ): AsyncResult<FormSubmission>;
  /** The open form behind a share link, for a respondent without an account. */
  getPublic(token: string): AsyncResult<PublicForm>;
  submitPublic(
    token: string,
    answers: FormAnswers,
    options?: PublicSubmitOptions,
  ): AsyncResult<PublicSubmission>;
  getSubmission(id: string): AsyncResult<FormSubmission>;
  /** Newest first. */
  listSubmissions(
    formId: string,
    options?: SubmissionListOptions,
  ): AsyncResult<readonly FormSubmission[]>;
  review(
    id: string,
    status: "accepted" | "rejected" | "submitted",
  ): AsyncResult<FormSubmission>;
  deleteSubmission(id: string): AsyncResult<boolean>;
  /**
   * The Net Promoter Score of the form's submitted and accepted answers, for
   * reviewers.
   */
  nps(formId: string, options?: NpsOptions): AsyncResult<FormNps>;
}

const FORM_STATUSES: readonly FormStatus[] = [
  "draft",
  "open",
  "closed",
  "archived",
];

const SUBMISSION_STATUSES: readonly FormSubmissionStatus[] = [
  "draft",
  "submitted",
  "accepted",
  "rejected",
];

const SOURCES: readonly FormSubmissionSource[] = [
  "member",
  "public",
  "service",
];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function formOf(value: unknown, fn: string): Form {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], FORM_STATUSES, "form status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("currentVersionId", optionalText(row["currentVersionId"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function definitionOf(value: unknown, fn: string): FormDefinition {
  if (!isFormDefinition(value)) {
    throw new TypeError(`${fn} returned a definition without steps`);
  }

  return value;
}

function versionOf(value: unknown, fn: string): FormVersion {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    formId: textOf(row["formId"]),
    number: Number(row["number"]),
    definition: definitionOf(row["definition"], fn),
    // SAFETY: the stored schema is the jsonb object form_schema() generated.
    schema: recordOf(row["schema"], fn) as FormJsonSchema,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function submissionOf(value: unknown, fn: string): FormSubmission {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    formId: textOf(row["formId"]),
    versionId: textOf(row["versionId"]),
    // SAFETY: the answers column holds a jsonb object of JSON values.
    answers: recordOrEmpty(row["answers"]) as FormAnswers,
    status: enumOrThrow(
      row["status"],
      SUBMISSION_STATUSES,
      "submission status",
    ),
    source: enumOrThrow(row["source"], SOURCES, "submission source"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("subjectType", optionalText(row["subjectType"])),
    ...optional("subjectId", optionalText(row["subjectId"])),
    ...optional("respondentId", optionalText(row["respondentId"])),
    ...optional("reviewedBy", optionalText(row["reviewedBy"])),
    ...optional("reviewedAt", optionalInstant(row["reviewedAt"])),
    ...optional("submittedAt", optionalInstant(row["submittedAt"])),
    ...optional("score", scoreOf(row)),
  };
}

function scoreOf(
  row: Readonly<Record<string, unknown>>,
): FormScore | undefined {
  if (row["score"] === null || row["score"] === undefined) {
    return undefined;
  }

  const passed = row["passed"];

  return {
    score: Number(row["score"]),
    maxScore: Number(row["maxScore"]),
    ...(typeof passed === "boolean" ? { passed } : {}),
  };
}

function npsCountsOf(row: Readonly<Record<string, unknown>>): NpsCounts {
  return {
    responses: Number(row["responses"]),
    promoters: Number(row["promoters"]),
    passives: Number(row["passives"]),
    detractors: Number(row["detractors"]),
    ...optional(
      "score",
      row["score"] === null || row["score"] === undefined
        ? undefined
        : Number(row["score"]),
    ),
  };
}

function npsOf(value: unknown): FormNps {
  const row = recordOf(value, "form_nps");

  return {
    ...npsCountsOf(row),
    field: textOf(row["field"]),
    periods: recordsOf(row["periods"], "form_nps").map((period) => ({
      ...npsCountsOf(period),
      start: requiredInstant(period["start"], "start"),
    })),
  };
}

/** The `forms` SQL module as typed calls. */
export function createForms<S extends StandardSchemaV1 | undefined = undefined>(
  options: FormsOptions<S>,
): Forms<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "form fields");

  const parsed = <T extends Form>(form: T): AsyncResult<T & Form<F>> =>
    AsyncResult.from(() => fields.read(form.fields)).map((value) => ({
      ...form,
      fields: value,
    }));

  /**
   * `{ fields }` for a write that sets extra columns, checked first; `{}`
   * otherwise.
   */
  const extra = (
    input: Readonly<Record<string, unknown>> | undefined,
  ): AsyncResult<{ readonly fields?: Readonly<Record<string, unknown>> }> =>
    input === undefined
      ? AsyncResult.ok({})
      : AsyncResult.from(() => fields.write({ ...input })).map((valid) => ({
          fields: valid,
        }));

  const client: Forms<F> = {
    create: (input) =>
      extra(input.fields)
        .andThen((set) =>
          call(
            "create_form",
            {
              tenant: input.organizationId,
              key: input.key,
              title: input.title,
              description: input.description ?? null,
              ...set,
            },
            (value) => formOf(value, "create_form"),
          ),
        )
        .andThen(parsed),
    update: (id, update) =>
      extra(update.fields)
        .andThen((set) =>
          call(
            "update_form",
            {
              form_id: id,
              title: update.title ?? null,
              description: update.description ?? null,
              status: update.status ?? null,
              ...set,
            },
            (value) => formOf(value, "update_form"),
          ),
        )
        .andThen(parsed),
    publish: (formId, definition) =>
      call("publish_form_version", { form_id: formId, definition }, (value) =>
        versionOf(value, "publish_form_version"),
      ),
    get: (id) =>
      call("get_form", { form_id: id }, (value) => {
        const row = recordOf(value, "get_form");

        return {
          ...formOf(row, "get_form"),
          ...optional(
            "version",
            row["version"] === null || row["version"] === undefined
              ? undefined
              : versionOf(row["version"], "get_form"),
          ),
        };
      }).andThen(parsed),
    getVersion: (versionId) =>
      call("get_form_version", { version_id: versionId }, (value) =>
        versionOf(value, "get_form_version"),
      ),
    list: (organizationId, list = {}) =>
      call(
        "list_forms",
        { tenant: organizationId, status: list.status ?? null },
        (value) =>
          recordsOf(value, "list_forms").map((row) =>
            formOf(row, "list_forms"),
          ),
      ).andThen((forms) =>
        AsyncResult.from(async () => {
          const out: Form<F>[] = [];

          for (const form of forms) {
            const read = await parsed(form);

            if (!read.ok) {
              return read;
            }

            out.push(read.data);
          }

          return ok(out);
        }),
      ),
    submit: (formId, answers, submit = {}) =>
      call(
        "submit_form",
        {
          form_id: formId,
          answers,
          subject_type: submit.subjectType ?? null,
          subject_id: submit.subjectId ?? null,
          submission_id: submit.submissionId ?? null,
          draft: submit.draft ?? false,
        },
        (value) => submissionOf(value, "submit_form"),
      ),
    getPublic: (token) =>
      call("get_public_form", { token }, (value) => {
        const row = recordOf(value, "get_public_form");

        return {
          id: textOf(row["id"]),
          title: textOf(row["title"]),
          version: versionOf(row["version"], "get_public_form"),
          ...optional("description", optionalText(row["description"])),
        };
      }),
    submitPublic: (token, answers, submit = {}) =>
      call(
        "submit_public_form",
        { token, answers, bot_token: submit.botToken ?? null },
        (value) => {
          const row = recordOf(value, "submit_public_form");

          return {
            id: textOf(row["id"]),
            status: enumOrThrow(
              row["status"],
              SUBMISSION_STATUSES,
              "submission status",
            ),
            ...optional("submittedAt", optionalInstant(row["submittedAt"])),
          };
        },
      ),
    getSubmission: (id) =>
      call("get_form_submission", { submission_id: id }, (value) =>
        submissionOf(value, "get_form_submission"),
      ),
    listSubmissions: (formId, list = {}) =>
      call(
        "list_form_submissions",
        {
          form_id: formId,
          status: list.status ?? null,
          page_size: list.pageSize ?? null,
          before: instantArg(list.before) ?? null,
        },
        (value) =>
          recordsOf(value, "list_form_submissions").map((row) =>
            submissionOf(row, "list_form_submissions"),
          ),
      ),
    review: (id, status) =>
      call("review_form_submission", { submission_id: id, status }, (value) =>
        submissionOf(value, "review_form_submission"),
      ),
    deleteSubmission: (id) =>
      call(
        "delete_form_submission",
        { submission_id: id },
        (value) => value === true,
      ),
    nps: (formId, nps = {}) =>
      call(
        "form_nps",
        {
          form_id: formId,
          field: nps.field ?? null,
          since: instantArg(nps.since) ?? null,
          until: instantArg(nps.until) ?? null,
          bucket: nps.bucket ?? null,
        },
        npsOf,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "forms",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
