import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { DEFAULT_MEETING_KINDS } from "./meetings-values.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.meetings.options";

const KEY = /^[a-z][a-z0-9_]{0,62}$/;

/** `options.kinds`, checked as a list of unique keys. */
function meetingKinds(ctx: BlockSqlContext): readonly string[] {
  const values = ctx.list("kinds", DEFAULT_MEETING_KINDS);

  if (values.length === 0) {
    throw new TypeError(`${WHERE}.kinds must name at least one value`);
  }

  for (const value of values) {
    if (!KEY.test(value)) {
      throw new TypeError(
        `${WHERE}.kinds: "${value}" must be lowercase letters, digits and underscores`,
      );
    }
  }

  if (new Set(values).size !== values.length) {
    throw new TypeError(`${WHERE}.kinds lists a value twice`);
  }

  return values;
}

/** Another block's context when it is installed with its tables. */
export const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

/** The SQL pieces the meetings files share. */
export interface MeetingsSql {
  readonly fn: (name: string) => string;
  /** A column of the meetings table. */
  readonly m: (column: string) => string;
  /** A column of the attendees table. */
  readonly a: (column: string) => string;
  /** A column of the agenda items table. */
  readonly g: (column: string) => string;
  /** A column of the decisions table. */
  readonly d: (column: string) => string;
  /** A column of the action items table. */
  readonly x: (column: string) => string;
  /** `row.column`, or `null` when the table lacks the column. */
  readonly of: (table: string, row: string, column: string) => string;
  readonly meetings: string;
  readonly attendees: string;
  readonly agenda: string;
  readonly decisions: string;
  readonly actions: string;
  /** The subject types, after renames, as SQL literals. */
  readonly subject: string;
  readonly decisionSubject: string;
  readonly kinds: string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  /**
   * The caller manages meetings, or writes them and created `meeting` or is its
   * chair or secretary.
   */
  readonly runs: (row: string) => string;
  /** The caller reads meetings, or is an attendee of `meeting`. */
  readonly sees: (tenant: string, meeting: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly agendaMissing: string;
  readonly decisionMissing: string;
  readonly statusInvalid: (row: string, to: string) => string;
  readonly meetingJson: (row: string) => string;
  readonly attendeeJson: (row: string) => string;
  readonly agendaJson: (row: string) => string;
  readonly decisionJson: (row: string) => string;
  /** Records a `meeting.*` event of a meetings row. */
  readonly record: (
    type: string,
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function meetingsSql(ctx: BlockSqlContext): MeetingsSql {
  const m = (column: string): string => ctx.col("meetings", column);
  const a = (column: string): string => ctx.col("attendees", column);
  const g = (column: string): string => ctx.col("agenda", column);
  const d = (column: string): string => ctx.col("decisions", column);
  const x = (column: string): string => ctx.col("actions", column);
  const fn = (name: string): string => ctx.fn(name);

  const of = (table: string, row: string, column: string): string =>
    ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

  const read = ctx.permission("read", OPERATIONS["meetings.read"]);
  const write = ctx.permission("write", OPERATIONS["meetings.write"]);
  const manage = ctx.permission("manage", OPERATIONS["meetings.manage"]);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const kinds = meetingKinds(ctx)
    .map((kind) => sqlString(kind))
    .join(", ");

  return {
    fn,
    m,
    a,
    g,
    d,
    x,
    of,
    meetings: ctx.table("meetings"),
    attendees: ctx.table("attendees"),
    agenda: ctx.table("agenda"),
    decisions: ctx.table("decisions"),
    actions: ctx.table("actions"),
    subject: sqlString(ctx.naming.rename("meeting")),
    decisionSubject: sqlString(ctx.naming.rename("meeting_decision")),
    kinds: `array[${kinds}]::text[]`,
    read,
    write,
    manage,
    allowed,
    runs: (row) =>
      `(${allowed(`${row}.${m("tenant")}`, manage)} or (auth.uid() is not null and ${ctx.can("tenant", `${row}.${m("tenant")}`, write)} and (coalesce(${of("meetings", row, "createdBy")} = auth.uid(), false) or coalesce(${fn("meeting_role")}(${row}.${m("id")}) in ('chair', 'secretary'), false))))`,
    sees: (tenant, meeting) =>
      `(${allowed(tenant, read)} or ${fn("meeting_role")}(${meeting}) is not null)`,
    invalid: (message) => fail("MEETING_INVALID", message, "22023"),
    forbidden: (message) => fail("MEETING_FORBIDDEN", message),
    missing: fail("MEETING_NOT_FOUND", "no such meeting", "P0002"),
    agendaMissing: fail(
      "MEETING_AGENDA_ITEM_NOT_FOUND",
      "no such agenda item",
      "P0002",
    ),
    decisionMissing: fail(
      "MEETING_DECISION_NOT_FOUND",
      "no such decision",
      "P0002",
    ),
    statusInvalid: (row, to) =>
      `raise exception 'the meeting can''t move from % to %', ${row}.${m("status")}, ${sqlString(to)} using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', ${row}.${m("status")}, 'to', ${sqlString(to)})::text;`,
    meetingJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'kind', ${row}.${m("kind")}, 'title', ${row}.${m("title")}, 'location', ${of("meetings", row, "location")}, 'startsAt', ${row}.${m("startsAt")}, 'endsAt', ${row}.${m("endsAt")}, 'status', ${row}.${m("status")}, 'startedAt', ${row}.${m("startedAt")}, 'heldAt', ${row}.${m("heldAt")}, 'summary', ${of("meetings", row, "summary")}, 'createdBy', ${of("meetings", row, "createdBy")}, 'createdAt', ${row}.${m("createdAt")}, 'updatedAt', ${row}.${m("updatedAt")})`,
    attendeeJson: (row) =>
      `jsonb_build_object('meetingId', ${row}.${a("meeting")}, 'userId', ${row}.${a("user")}, 'role', ${row}.${a("role")}, 'attendance', ${row}.${a("attendance")})`,
    agendaJson: (row) =>
      `jsonb_build_object('id', ${row}.${g("id")}, 'meetingId', ${row}.${g("meeting")}, 'ordinal', ${row}.${g("ordinal")}, 'title', ${row}.${g("title")}, 'notes', ${of("agenda", row, "notes")}, 'presenterId', ${row}.${g("presenter")}, 'minutes', ${row}.${g("minutes")}, 'status', ${row}.${g("status")}, 'outcome', ${of("agenda", row, "outcome")})`,
    decisionJson: (row) =>
      `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'meetingId', ${row}.${d("meeting")}, 'agendaItemId', ${row}.${d("agendaItem")}, 'title', ${row}.${d("title")}, 'body', ${of("decisions", row, "body")}, 'status', ${row}.${d("status")}, 'decidedBy', ${row}.${d("decidedBy")}, 'decidedAt', ${row}.${d("decidedAt")}, 'createdAt', ${row}.${d("createdAt")})`,
    record: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'kind', ${row}.${m("kind")}, 'title', ${row}.${m("title")}, 'status', ${row}.${m("status")}${extra})`,
        subject: `'meetings/' || ${row}.${m("id")}::text`,
        tenant: `${row}.${m("tenant")}`,
        audit: {
          category: "data",
          targetType: "meeting",
          recordId: `${row}.${m("id")}::text`,
          targetLabel: `${row}.${m("title")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
