import "server-only";
import type {
  MeetingAttendeeRole,
  MeetingDecisionStatus,
  MeetingStatus,
} from "better-supabase/blocks/meetings";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** A meeting as the agenda list shows it, serializable. */
export interface MeetingRow {
  readonly id: string;
  readonly title: string;
  readonly kind: string;
  readonly status: MeetingStatus;
  readonly location: string | null;
  readonly startsAt: string;
}

async function loadMeetings(): Promise<readonly MeetingRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const meetings = await db.meetings.list({ limit: 200 }).orThrow();

  return meetings.map((row) => ({
    id: row.id,
    title: row.title,
    kind: row.kind,
    status: row.status,
    location: row.location ?? null,
    startsAt: row.startsAt.toString(),
  }));
}

/** The organization's meetings, the most recent first. */
export function getMeetings(): Promise<Loaded<readonly MeetingRow[]>> {
  return settle(loadMeetings);
}

/** The meeting the minutes panel shows, serializable. */
export interface MeetingMinutesView {
  readonly id: string;
  readonly title: string;
  readonly status: MeetingStatus;
  readonly attendees: readonly {
    readonly userId: string;
    readonly role: MeetingAttendeeRole;
  }[];
  readonly agenda: readonly {
    readonly id: string;
    readonly ordinal: number;
    readonly title: string;
    readonly minutes: string | null;
    readonly outcome: string | null;
  }[];
  readonly decisions: readonly {
    readonly id: string;
    readonly title: string;
    readonly status: MeetingDecisionStatus;
    readonly up: number;
    readonly down: number;
  }[];
  readonly actionItems: readonly {
    readonly workItemId: string;
    readonly title: string;
    readonly state: string;
  }[];
}

async function loadMinutes(
  meetingId: string,
): Promise<MeetingMinutesView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const detail = await db.meetings.get(meetingId).orThrow();

  return {
    id: detail.id,
    title: detail.title,
    status: detail.status,
    attendees: detail.attendees.map((attendee) => ({
      userId: attendee.userId,
      role: attendee.role,
    })),
    agenda: detail.agenda.map((item) => ({
      id: item.id,
      ordinal: item.ordinal,
      title: item.title,
      minutes: item.minutes ?? null,
      outcome: item.outcome ?? null,
    })),
    decisions: detail.decisions.map((decision) => ({
      id: decision.id,
      title: decision.title,
      status: decision.status,
      up: decision.votes?.up ?? 0,
      down: decision.votes?.down ?? 0,
    })),
    actionItems: detail.actionItems.map((item) => ({
      workItemId: item.workItemId,
      title: item.title,
      state: item.state,
    })),
  };
}

/** A meeting with its attendees, agenda, decisions and action items. */
export function getMeetingMinutes(
  meetingId: string,
): Promise<Loaded<MeetingMinutesView>> {
  return settle(() => loadMinutes(meetingId));
}
