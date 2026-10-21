import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";
import type { MyWorkKind } from "./my-work-kinds.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectKey } from "../../core/block-subjects.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
} from "../shared.ts";
import { MY_WORK_KINDS } from "./my-work-kinds.ts";

/** The most refs one `subject_titles` call takes; `resolve` splits above it. */
export const SUBJECT_TITLES_LIMIT = 500;

export interface SubjectsOptions extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Subjects>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** A subject with its title and path, from `config.subjects`. */
export interface ResolvedSubject extends SubjectRef {
  /** The `title` column's value, when the type names one. */
  readonly title?: string;
  /** The `url` template filled in, such as `/customers/42`. */
  readonly url?: string;
}

/** A record page's header and tab badges, from `record_summary`. */
export interface RecordSummary extends ResolvedSubject {
  /** Rows per section the caller can read, for each installed section asked. */
  readonly counts: Readonly<Record<string, number>>;
  /** Per section, whether a row is newer than `seenAt`. */
  readonly unread: Readonly<Record<string, boolean>>;
}

export interface RecordSummaryOptions {
  /** When the caller last saw the record; every section is read without it. */
  readonly seenAt?: Temporal.Instant | null;
}

/** One thing waiting on the caller, from `my_work`. */
export interface MyWorkItem {
  readonly kind: MyWorkKind;
  /** The record it is about: the work item, or the approval's subject. */
  readonly subject: SubjectRef;
  /**
   * The row that put it here: the work item, approval request, reminder,
   * comment or SLA clock id.
   */
  readonly ref: string;
  readonly title?: string;
  readonly url?: string;
  /** The due date, or when it arrived. */
  readonly at?: Temporal.Instant;
}

/** The most items one `my_work` call returns. */
export const MY_WORK_LIMIT = 200;

export interface MyWorkOptions {
  /** Only this organization's work. Default: every organization. */
  readonly tenant?: string;
  /** At most this many items, newest first. Default 50, at most 200. */
  readonly pageSize?: number;
}

/** The subjects block's registry as typed calls. */
export interface Subjects {
  /**
   * Titles and paths for many subjects in one call, keyed by `subjectKey`
   * (`type:id`). A subject the caller can't read, a soft-deleted row or an
   * unknown type is left out.
   */
  resolve(
    refs: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, ResolvedSubject>>>;
  /**
   * The subject's title and path with a count and unread state for each of
   * `sections` (`comments`, `attachments`), in one round trip; `undefined` when
   * the caller can't read the subject.
   */
  summary(
    subject: SubjectRef,
    sections: readonly string[],
    options?: RecordSummaryOptions,
  ): AsyncResult<RecordSummary | undefined>;
  /**
   * What waits on the caller across the installed blocks, newest first: open
   * work items assigned to them, approvals they can decide, their reminders
   * sent this week, recent mentions and SLA clocks warned on their work.
   */
  myWork(options?: MyWorkOptions): AsyncResult<readonly MyWorkItem[]>;
}

function resolvedOf(value: unknown): ResolvedSubject | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const type = optionalText(value["type"]);
  const id = optionalText(value["id"]);

  if (type === undefined || id === undefined) {
    return undefined;
  }

  const title = optionalText(value["title"]);
  const url = optionalText(value["url"]);

  return {
    type,
    id,
    ...(title === undefined ? {} : { title }),
    ...(url === undefined ? {} : { url }),
  };
}

function numbersOf(value: unknown): Record<string, number> {
  return isRecord(value)
    ? Object.fromEntries(
        Object.entries(value).flatMap(([key, each]) =>
          typeof each === "number" ? [[key, each]] : [],
        ),
      )
    : {};
}

function flagsOf(value: unknown): Record<string, boolean> {
  return isRecord(value)
    ? Object.fromEntries(
        Object.entries(value).flatMap(([key, each]) =>
          typeof each === "boolean" ? [[key, each]] : [],
        ),
      )
    : {};
}

function summaryOf(value: unknown): RecordSummary | undefined {
  const resolved = resolvedOf(value);

  return resolved === undefined || !isRecord(value)
    ? undefined
    : {
        ...resolved,
        counts: numbersOf(value["counts"]),
        unread: flagsOf(value["unread"]),
      };
}

function workOf(value: unknown): MyWorkItem | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const kind = MY_WORK_KINDS.find((each) => each === value["kind"]);
  const subject = resolvedOf(value["subject"]);
  const ref = optionalText(value["ref"]);

  if (kind === undefined || subject === undefined || ref === undefined) {
    return undefined;
  }

  const title = optionalText(value["title"]);
  const url = optionalText(value["url"]);
  const at = optionalInstant(value["at"]);

  return {
    kind,
    subject: { type: subject.type, id: subject.id },
    ref,
    ...(title === undefined ? {} : { title }),
    ...(url === undefined ? {} : { url }),
    ...(at === undefined ? {} : { at }),
  };
}

const workList = (value: unknown): MyWorkItem[] =>
  (Array.isArray(value) ? value : []).flatMap((row) => {
    const item = workOf(row);

    return item === undefined ? [] : [item];
  });

const resolvedList = (value: unknown): ResolvedSubject[] =>
  (Array.isArray(value) ? value : []).flatMap((row) => {
    const resolved = resolvedOf(row);

    return resolved === undefined ? [] : [resolved];
  });

/**
 * The `subjects` module's `subject_titles` as a typed call, for lists and
 * mentions that show a link to each subject.
 */
export function createSubjects(options: SubjectsOptions): Subjects {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Subjects = {
    resolve: (refs) =>
      AsyncResult.from(async () => {
        const unique = [
          ...new Map(refs.map((ref) => [subjectKey(ref), ref])).values(),
        ];

        const chunks: SubjectRef[][] = [];

        for (
          let start = 0;
          start < unique.length;
          start += SUBJECT_TITLES_LIMIT
        ) {
          chunks.push(unique.slice(start, start + SUBJECT_TITLES_LIMIT));
        }

        const results = await Promise.all(
          chunks.map((chunk) =>
            call(
              "subject_titles",
              { refs: chunk.map(({ type, id }) => ({ type, id })) },
              resolvedList,
            ),
          ),
        );

        const found: Record<string, ResolvedSubject> = {};

        for (const result of results) {
          if (!result.ok) {
            return result;
          }

          for (const subject of result.data) {
            found[subjectKey(subject)] = subject;
          }
        }

        return ok(found);
      }),
    summary: (subject, sections, summaryOptions = {}) =>
      call(
        "record_summary",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          sections: [...sections],
          seen_at: instantArg(summaryOptions.seenAt) ?? null,
        },
        summaryOf,
      ),
    myWork: (workOptions = {}) =>
      call(
        "my_work",
        {
          tenant: workOptions.tenant ?? null,
          page_size: workOptions.pageSize ?? 50,
        },
        workList,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "subjects",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
