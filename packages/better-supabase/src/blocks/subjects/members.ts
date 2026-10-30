import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { CursorPageOptions } from "../shared.ts";

import { temporal } from "../../core/temporal-required.ts";
import {
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
} from "../shared.ts";

/** The most records one `members.mine` call returns. */
export const MY_SUBJECTS_LIMIT = 200;

/** One row of a record's team, from `subject_members`. */
export interface SubjectMember {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  /** Set for a user on the team. */
  readonly userId?: string;
  /** Set for a team on the team. */
  readonly teamId?: string;
  /** One of `blocks.subjects.options.recordTeam.roles`. */
  readonly role: string;
  /** The first day the membership counts; from the start without it. */
  readonly startsOn?: Temporal.PlainDate;
  /** The last day the membership counts; open-ended without it. */
  readonly endsOn?: Temporal.PlainDate;
  /** An emergency (break-the-glass) entry, with its `reason`. */
  readonly emergency: boolean;
  readonly reason?: string;
  /** Whether the dates include today, so the membership grants access. */
  readonly active: boolean;
  readonly createdBy?: string;
  readonly createdAt?: Temporal.Instant;
}

interface SubjectMemberDates {
  /** Default `member`. */
  readonly role?: string;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
}

/** Who `members.add` puts on the record's team: one user or one team. */
export type SubjectMemberInput =
  | (SubjectMemberDates & { readonly userId: string; readonly teamId?: never })
  | (SubjectMemberDates & { readonly teamId: string; readonly userId?: never });

export interface EndSubjectMemberOptions {
  /** The last day the membership counts. Default: today, in the database. */
  readonly endsOn?: Temporal.PlainDate;
}

/** A record whose team the caller is on today, from `my_subjects`. */
export interface MySubject {
  readonly subject: RecordRef;
  readonly organizationId: string;
  /** The caller's roles on the record, directly and through their teams. */
  readonly roles: readonly string[];
  /** The last day of the caller's latest-ending membership, when all end. */
  readonly endsOn?: Temporal.PlainDate;
  readonly emergency: boolean;
  readonly title?: string;
  readonly url?: string;
}

/** `cursor` is the previous page's `nextCursor`. */
export interface MySubjectsOptions extends CursorPageOptions<string> {
  /** Only records of this subject type. */
  readonly subjectType?: string;
}

export interface MySubjectsPage {
  /** By subject type, then id. */
  readonly items: readonly MySubject[];
  /** The cursor of the next page, or null on the last one. */
  readonly nextCursor: string | null;
}

/** A record's team (`config.subjects.<type>.team`, ADR 0134). */
export interface SubjectMembers {
  /**
   * Puts a user or a team on the record's team, or reopens their membership in
   * that role with the new dates. Needs `subjects.manage` in the record's
   * organization, or `manage` on the record.
   */
  add(
    subject: RecordRef,
    member: SubjectMemberInput,
  ): AsyncResult<SubjectMember>;
  /** Ends a membership: it counts through `endsOn`, then access stops. */
  end(
    memberId: string,
    options?: EndSubjectMemberOptions,
  ): AsyncResult<SubjectMember>;
  /** The record's team, current and past, for a caller who can read it. */
  list(subject: RecordRef): AsyncResult<readonly SubjectMember[]>;
  /** The records whose team the caller is on today, a page at a time. */
  mine(
    tenant: string,
    options?: MySubjectsOptions,
  ): AsyncResult<MySubjectsPage>;
}

const dateOf = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

const dateArg = (value: Temporal.PlainDate | undefined): string | null =>
  value === undefined ? null : value.toString();

function memberOf(value: unknown): SubjectMember {
  const row = recordOf(value, "subject member");
  const userId = optionalText(row["userId"]);
  const teamId = optionalText(row["teamId"]);
  const startsOn = dateOf(row["startsOn"]);
  const endsOn = dateOf(row["endsOn"]);
  const reason = optionalText(row["reason"]);
  const createdBy = optionalText(row["createdBy"]);
  const createdAt = optionalInstant(row["createdAt"]);

  return {
    id: optionalText(row["id"]) ?? "",
    organizationId: optionalText(row["organizationId"]) ?? "",
    subject: {
      type: optionalText(row["subjectType"]) ?? "",
      id: optionalText(row["subjectId"]) ?? "",
    },
    ...(userId === undefined ? {} : { userId }),
    ...(teamId === undefined ? {} : { teamId }),
    role: optionalText(row["role"]) ?? "",
    ...(startsOn === undefined ? {} : { startsOn }),
    ...(endsOn === undefined ? {} : { endsOn }),
    emergency: row["emergency"] === true,
    ...(reason === undefined ? {} : { reason }),
    active: row["active"] === true,
    ...(createdBy === undefined ? {} : { createdBy }),
    ...(createdAt === undefined ? {} : { createdAt }),
  };
}

function mineOf(value: unknown): MySubject | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const type = optionalText(value["subjectType"]);
  const id = optionalText(value["subjectId"]);

  if (type === undefined || id === undefined) {
    return undefined;
  }

  const endsOn = dateOf(value["endsOn"]);
  const title = optionalText(value["title"]);
  const url = optionalText(value["url"]);
  const roles = value["roles"];

  return {
    subject: { type, id },
    organizationId: optionalText(value["organizationId"]) ?? "",
    roles: Array.isArray(roles)
      ? roles.flatMap((role) => (typeof role === "string" ? [role] : []))
      : [],
    ...(endsOn === undefined ? {} : { endsOn }),
    emergency: value["emergency"] === true,
    ...(title === undefined ? {} : { title }),
    ...(url === undefined ? {} : { url }),
  };
}

function pageOfMine(value: unknown): MySubjectsPage {
  const row = recordOf(value, "my_subjects");
  const items = Array.isArray(row["items"]) ? row["items"] : [];

  return {
    items: items.flatMap((item) => {
      const mine = mineOf(item);

      return mine === undefined ? [] : [mine];
    }),
    nextCursor: optionalText(row["nextCursor"]) ?? null,
  };
}

const memberList = (value: unknown): SubjectMember[] =>
  (Array.isArray(value) ? value : []).map(memberOf);

/** `members` of the subjects client, over `call`. */
export function subjectMembers(call: BlockCall): SubjectMembers {
  return {
    add: (subject, member) =>
      call(
        "add_subject_member",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          user_id: member.userId ?? null,
          team_id: member.teamId ?? null,
          role: member.role ?? "member",
          starts_on: dateArg(member.startsOn),
          ends_on: dateArg(member.endsOn),
        },
        memberOf,
      ),
    end: (memberId, options = {}) =>
      call(
        "end_subject_member",
        {
          member_id: memberId,
          ...(options.endsOn === undefined
            ? {}
            : { ends_on: options.endsOn.toString() }),
        },
        memberOf,
      ),
    list: (subject) =>
      call(
        "list_subject_members",
        { subject_type: subject.type, subject_id: subject.id },
        memberList,
      ),
    mine: (tenant, options = {}) =>
      call(
        "my_subjects",
        {
          tenant,
          subject_type: options.subjectType ?? null,
          page_size: options.limit ?? 100,
          cursor: options.cursor ?? null,
        },
        pageOfMine,
      ),
  };
}
