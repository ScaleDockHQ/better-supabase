import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  MEETING_AGENDA_STATUSES,
  MEETING_ATTENDANCE,
  MEETING_ATTENDEE_ROLES,
  MEETING_DECISION_STATUSES,
  MEETING_STATUSES,
} from "../../sql/modules/meetings-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a meeting stands. */
export type MeetingStatus = (typeof MEETING_STATUSES)[number];

/** What an attendee does at a meeting. */
export type MeetingAttendeeRole = (typeof MEETING_ATTENDEE_ROLES)[number];

/** Whether an attendee was there. */
export type MeetingAttendance = (typeof MEETING_ATTENDANCE)[number];

/** Where an agenda item stands. */
export type MeetingAgendaStatus = (typeof MEETING_AGENDA_STATUSES)[number];

/** Where a decision stands. */
export type MeetingDecisionStatus = (typeof MEETING_DECISION_STATUSES)[number];

/** A meeting. `F` types the extra columns. */
export interface Meeting<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** One of `options.kinds`. */
  readonly kind: string;
  readonly title: string;
  readonly location?: string;
  readonly startsAt: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  readonly status: MeetingStatus;
  readonly startedAt?: Temporal.Instant;
  readonly heldAt?: Temporal.Instant;
  readonly summary?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** Who is invited to a meeting. */
export interface MeetingAttendee {
  readonly userId: string;
  readonly role: MeetingAttendeeRole;
  readonly attendance: MeetingAttendance;
}

/** One item of a meeting's agenda, with its minutes. */
export interface MeetingAgendaItem {
  readonly id: string;
  readonly meetingId: string;
  /** 1, 2, 3 within the meeting. */
  readonly ordinal: number;
  readonly title: string;
  readonly notes?: string;
  readonly presenterId?: string;
  /** The minutes of this item, in Markdown. */
  readonly minutes?: string;
  readonly status: MeetingAgendaStatus;
  readonly outcome?: string;
}

/** The votes on a decision, from the reactions block. */
export interface MeetingDecisionVotes {
  readonly score: number;
  readonly up: number;
  readonly down: number;
  /** The caller's vote: 1, -1 or 0. */
  readonly vote: number;
}

/** A decision of a meeting. */
export interface MeetingDecision {
  readonly id: string;
  readonly organizationId: string;
  readonly meetingId: string;
  readonly agendaItemId?: string;
  readonly title: string;
  readonly body?: string;
  readonly status: MeetingDecisionStatus;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  /** Present on `get` when the reactions block is installed. */
  readonly votes?: MeetingDecisionVotes;
}

/** A task opened from a meeting. */
export interface MeetingActionItem {
  /** The work item the `tasks` block owns. */
  readonly workItemId: string;
  readonly title: string;
  readonly state: string;
  readonly dueAt?: Temporal.Instant;
  readonly agendaItemId?: string;
  readonly decisionId?: string;
}

/** A meeting with its attendees, agenda, decisions and action items. */
export interface MeetingDetail<
  F extends object = Record<never, never>,
> extends Meeting<F> {
  readonly attendees: readonly MeetingAttendee[];
  readonly agenda: readonly MeetingAgendaItem[];
  readonly decisions: readonly MeetingDecision[];
  readonly actionItems: readonly MeetingActionItem[];
}

export interface MeetingInput<F extends object = Record<never, never>> {
  /** One of `options.kinds`. Default: the first one. */
  readonly kind?: string;
  readonly title: string;
  readonly location?: string | null;
  readonly startsAt: Temporal.Instant;
  readonly endsAt?: Temporal.Instant | null;
  /** The invited users; at most one chair. */
  readonly attendees?: readonly {
    readonly userId: string;
    readonly role?: MeetingAttendeeRole;
    readonly attendance?: MeetingAttendance;
  }[];
  /** The agenda, in order. */
  readonly agenda?: readonly {
    readonly title: string;
    readonly notes?: string | null;
    readonly presenterId?: string | null;
  }[];
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** What `update` changes; keys left out keep their value. */
export type MeetingChange<F extends object = Record<never, never>> = Partial<
  Omit<MeetingInput<F>, "attendees" | "agenda"> & {
    readonly summary: string | null;
  }
>;

export interface MeetingAgendaItemInput {
  /** Changes this item instead of adding one. */
  readonly id?: string;
  readonly title?: string;
  readonly notes?: string | null;
  readonly presenterId?: string | null;
  readonly minutes?: string | null;
  readonly status?: MeetingAgendaStatus;
  readonly outcome?: string | null;
  /** Where the item goes; the items from there move down. Default: last. */
  readonly ordinal?: number;
}

export interface MeetingDecisionInput {
  readonly title: string;
  readonly body?: string | null;
  readonly agendaItemId?: string | null;
  /** Default `proposed`. */
  readonly status?: MeetingDecisionStatus;
}

/** What `addActionItem` takes besides the task itself. */
export interface MeetingActionItemInput {
  /** The task, as `create_task` takes it: `{ title, dueAt, ... }`. */
  readonly task: Readonly<Record<string, unknown>>;
  readonly assignees?: readonly string[];
  readonly agendaItemId?: string;
  readonly decisionId?: string;
}

export interface MeetingListOptions {
  readonly kind?: string;
  readonly status?: MeetingStatus;
  /** Starting on or after. */
  readonly from?: Temporal.Instant;
  /** Starting on or before. */
  readonly to?: Temporal.Instant;
  readonly attendeeId?: string;
  /** Matches the title, location or summary. */
  readonly search?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface Meetings<F extends object = Record<never, never>> {
  /** Plans a meeting; needs `meetings.write`. */
  create(input: MeetingInput<F>): AsyncResult<Meeting<F>>;
  /**
   * Changes a meeting, as its creator, chair or secretary or with
   * `meetings.manage`.
   */
  update(input: {
    meetingId: string;
    change: MeetingChange<F>;
  }): AsyncResult<Meeting<F>>;
  start(meetingId: string): AsyncResult<Meeting<F>>;
  /** Closes the meeting as held, with an optional summary. */
  hold(input: {
    meetingId: string;
    summary?: string | undefined;
  }): AsyncResult<Meeting<F>>;
  cancel(input: {
    meetingId: string;
    reason?: string | undefined;
  }): AsyncResult<Meeting<F>>;
  /** Deletes a planned or cancelled meeting. */
  delete(meetingId: string): AsyncResult<Meeting<F>>;
  /** Invites a user or changes their role or attendance. */
  setAttendee(input: {
    meetingId: string;
    userId: string;
    attendee?:
      | {
          readonly role?: MeetingAttendeeRole;
          readonly attendance?: MeetingAttendance;
        }
      | undefined;
  }): AsyncResult<MeetingAttendee>;
  removeAttendee(input: {
    meetingId: string;
    userId: string;
  }): AsyncResult<MeetingAttendee>;
  /** Adds an agenda item, or changes one when `item.id` is set. */
  saveAgendaItem(input: {
    meetingId: string;
    item: MeetingAgendaItemInput;
  }): AsyncResult<MeetingAgendaItem>;
  deleteAgendaItem(itemId: string): AsyncResult<MeetingAgendaItem>;
  /** Records a decision; attendees vote on it through the reactions block. */
  recordDecision(input: {
    meetingId: string;
    input: MeetingDecisionInput;
  }): AsyncResult<MeetingDecision>;
  /**
   * Decides a decision. Without a status it follows the votes: more up than
   * down passes, more down than up rejects, a tie defers.
   */
  decide(input: {
    decisionId: string;
    status?: Exclude<MeetingDecisionStatus, "proposed"> | undefined;
  }): AsyncResult<MeetingDecision>;
  /** Opens a task from the meeting through the tasks block. */
  addActionItem(input: {
    meetingId: string;
    input: MeetingActionItemInput;
  }): AsyncResult<Readonly<Record<string, unknown>>>;
  get(meetingId: string): AsyncResult<MeetingDetail<F>>;
  list(options?: MeetingListOptions): AsyncResult<readonly Meeting<F>[]>;
}

/** Options for {@link createMeetings}. */
export interface MeetingsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the meeting's extra columns
   * (`blocks.meetings.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Meetings<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const instantArg = (
  value: Temporal.Instant | null | undefined,
): string | null | undefined =>
  value === undefined ? undefined : value === null ? null : value.toString();

function meetingOf(value: unknown, fn: string): Meeting {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    title: textOf(row["title"]),
    startsAt: requiredInstant(row["startsAt"], "startsAt"),
    status: enumOrThrow(row["status"], MEETING_STATUSES, "meeting status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("location", optionalText(row["location"])),
    ...optional("endsAt", optionalInstant(row["endsAt"])),
    ...optional("startedAt", optionalInstant(row["startedAt"])),
    ...optional("heldAt", optionalInstant(row["heldAt"])),
    ...optional("summary", optionalText(row["summary"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function attendeeOf(value: unknown, fn: string): MeetingAttendee {
  const row = recordOf(value, fn);

  return {
    userId: textOf(row["userId"]),
    role: enumOrThrow(
      row["role"],
      MEETING_ATTENDEE_ROLES,
      "meeting attendee role",
    ),
    attendance: enumOrThrow(
      row["attendance"],
      MEETING_ATTENDANCE,
      "meeting attendance",
    ),
  };
}

function agendaOf(value: unknown, fn: string): MeetingAgendaItem {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    meetingId: textOf(row["meetingId"]),
    ordinal: Number(row["ordinal"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      MEETING_AGENDA_STATUSES,
      "meeting agenda status",
    ),
    ...optional("notes", optionalText(row["notes"])),
    ...optional("presenterId", optionalText(row["presenterId"])),
    ...optional("minutes", optionalText(row["minutes"])),
    ...optional("outcome", optionalText(row["outcome"])),
  };
}

function decisionOf(value: unknown, fn: string): MeetingDecision {
  const row = recordOf(value, fn);
  const votes = isRecord(row["votes"]) ? row["votes"] : undefined;

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    meetingId: textOf(row["meetingId"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      MEETING_DECISION_STATUSES,
      "meeting decision status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("agendaItemId", optionalText(row["agendaItemId"])),
    ...optional("body", optionalText(row["body"])),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"])),
    ...optional(
      "votes",
      votes === undefined
        ? undefined
        : {
            score: Number(votes["score"]),
            up: Number(votes["up"]),
            down: Number(votes["down"]),
            vote: Number(votes["vote"]),
          },
    ),
  };
}

function actionItemOf(
  value: Readonly<Record<string, unknown>>,
): MeetingActionItem {
  return {
    workItemId: textOf(value["workItemId"]),
    title: textOf(value["title"]),
    state: textOf(value["state"]),
    ...optional("dueAt", optionalInstant(value["dueAt"])),
    ...optional("agendaItemId", optionalText(value["agendaItemId"])),
    ...optional("decisionId", optionalText(value["decisionId"])),
  };
}

function detailOf(value: unknown, fn: string): MeetingDetail {
  const row = recordOf(value, fn);

  return {
    ...meetingOf(row, fn),
    attendees: recordsOf(row["attendees"], fn).map((entry) =>
      attendeeOf(entry, fn),
    ),
    agenda: recordsOf(row["agenda"], fn).map((entry) => agendaOf(entry, fn)),
    decisions: recordsOf(row["decisions"], fn).map((entry) =>
      decisionOf(entry, fn),
    ),
    actionItems: recordsOf(row["actionItems"], fn).map((entry) =>
      actionItemOf(entry),
    ),
  };
}

/** The `create_meeting` and `update_meeting` input, with checked fields. */
function meetingArgs(
  input: Partial<MeetingInput<object>> & { readonly summary?: string | null },
  checked: Readonly<Record<string, unknown>> | undefined,
): Record<string, unknown> {
  return definedOf({
    ...input,
    startsAt: instantArg(input.startsAt),
    endsAt: instantArg(input.endsAt),
    fields: checked,
  });
}

/**
 * Meetings: an agenda with minutes, attendees with roles, decisions the
 * attendees vote on, and action items that become tasks.
 */
export function createMeetings<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: MeetingsOptions<S>): Meetings<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const fields: BlockFields<F> = blockFields(options.fields, "meeting fields");

  const one = (fn: string) => (value: unknown) => meetingOf(value, fn);
  const decision = (fn: string) => (value: unknown) => decisionOf(value, fn);
  const attendee = (fn: string) => (value: unknown) => attendeeOf(value, fn);
  const agendaItem = (fn: string) => (value: unknown) => agendaOf(value, fn);

  const client: Meetings<F> = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "create_meeting",
              { tenant: organizationId, input: meetingArgs(input, checked) },
              one("create_meeting"),
            ).andThen(fields.row),
          ),
      ),
    update: ({ meetingId, change }) =>
      fields
        .args(change.fields)
        .andThen((checked) =>
          call(
            "update_meeting",
            { meeting_id: meetingId, changes: meetingArgs(change, checked) },
            one("update_meeting"),
          ).andThen(fields.row),
        ),
    start: (meetingId) =>
      call(
        "start_meeting",
        { meeting_id: meetingId },
        one("start_meeting"),
      ).andThen(fields.row),
    hold: ({ meetingId, summary }) =>
      call(
        "hold_meeting",
        { meeting_id: meetingId, summary: summary ?? null },
        one("hold_meeting"),
      ).andThen(fields.row),
    cancel: ({ meetingId, reason }) =>
      call(
        "cancel_meeting",
        { meeting_id: meetingId, reason: reason ?? null },
        one("cancel_meeting"),
      ).andThen(fields.row),
    delete: (meetingId) =>
      call(
        "delete_meeting",
        { meeting_id: meetingId },
        one("delete_meeting"),
      ).andThen(fields.row),
    setAttendee: ({ meetingId, userId, attendee: change = {} }) =>
      call(
        "set_meeting_attendee",
        {
          meeting_id: meetingId,
          user_id: userId,
          role: change.role ?? "attendee",
          attendance: change.attendance ?? null,
        },
        attendee("set_meeting_attendee"),
      ),
    removeAttendee: ({ meetingId, userId }) =>
      call(
        "remove_meeting_attendee",
        { meeting_id: meetingId, user_id: userId },
        attendee("remove_meeting_attendee"),
      ),
    saveAgendaItem: ({ meetingId, item }) =>
      call(
        "save_meeting_agenda_item",
        { meeting_id: meetingId, item: definedOf(item) },
        agendaItem("save_meeting_agenda_item"),
      ),
    deleteAgendaItem: (itemId) =>
      call(
        "delete_meeting_agenda_item",
        { item_id: itemId },
        agendaItem("delete_meeting_agenda_item"),
      ),
    recordDecision: ({ meetingId, input }) =>
      call(
        "record_meeting_decision",
        { meeting_id: meetingId, input: definedOf(input) },
        decision("record_meeting_decision"),
      ),
    decide: ({ decisionId, status }) =>
      call(
        "decide_meeting_decision",
        { decision_id: decisionId, status: status ?? null },
        decision("decide_meeting_decision"),
      ),
    addActionItem: ({ meetingId, input }) =>
      call(
        "add_meeting_action_item",
        {
          meeting_id: meetingId,
          task: input.task,
          assignees: input.assignees ?? [],
          agenda_item_id: input.agendaItemId ?? null,
          decision_id: input.decisionId ?? null,
        },
        (value) => recordOf(value, "add_meeting_action_item"),
      ),
    get: (meetingId) =>
      call("get_meeting", { meeting_id: meetingId }, (value) =>
        detailOf(value, "get_meeting"),
      ).andThen(fields.row),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_meetings",
          {
            tenant: organizationId,
            filters: definedOf({
              kind: list.kind,
              status: list.status,
              from: instantArg(list.from),
              to: instantArg(list.to),
              attendeeId: list.attendeeId,
              search: list.search,
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_meetings").map((row) =>
              meetingOf(row, "list_meetings"),
            ),
        ).andThen(fields.rows),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "meetings",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
