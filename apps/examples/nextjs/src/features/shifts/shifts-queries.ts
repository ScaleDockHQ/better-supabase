import "server-only";
import type {
  ShiftAssignmentStatus,
  ShiftStatus,
} from "better-supabase/blocks/shifts";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { readMemberNames } from "@/features/people/member-names";
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

/** A shift on the roster, serializable. */
export interface RosterRow {
  readonly id: string;
  /** `YYYY-MM-DD` in UTC, the block's default time zone. */
  readonly day: string;
  readonly startsAt: string;
  readonly endsAt: string;
  readonly status: ShiftStatus;
  readonly headcount: number;
  readonly assigned: number;
  readonly requested: number;
}

async function loadRoster(week: string): Promise<readonly RosterRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const monday = Temporal.PlainDate.from(week);

  const shifts = await db.shifts
    .roster({
      organizationId: tenant,
      from: monday,
      until: monday.add({ days: 6 }),
    })
    .orThrow();

  return shifts.map((shift) => ({
    id: shift.id,
    day: shift.startsAt.toZonedDateTimeISO("UTC").toPlainDate().toString(),
    startsAt: shift.startsAt.toString(),
    endsAt: shift.endsAt.toString(),
    status: shift.status,
    headcount: shift.headcount,
    assigned: shift.assignments.filter((a) => a.status === "assigned").length,
    requested: shift.assignments.filter((a) => a.status === "requested").length,
  }));
}

/** The shifts of the week from `week` (a Monday), with their filled places. */
export function getRoster(week: string): Promise<Loaded<readonly RosterRow[]>> {
  return settle(() => loadRoster(week));
}

/** One person on a shift, with the state of their place. */
export interface ShiftPerson {
  readonly id: string;
  readonly userId: string;
  readonly name: string;
  readonly status: ShiftAssignmentStatus;
}

export interface ShiftDetailData {
  readonly id: string;
  readonly startsAt: string;
  readonly endsAt: string;
  readonly status: ShiftStatus;
  readonly headcount: number;
  readonly breakMinutes: number;
  readonly note: string | null;
  readonly requiredQualifications: readonly string[];
  readonly people: readonly ShiftPerson[];
}

async function loadShift(
  id: string,
  from: string,
  until: string,
): Promise<ShiftDetailData | "not-found" | null> {
  "use cache: private";
  const scope = await bsb.cached();
  const { session, db } = scope;
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const shifts = await db.shifts
    .roster({
      organizationId: tenant,
      from: Temporal.PlainDate.from(from),
      until: Temporal.PlainDate.from(until),
    })
    .orThrow();

  const shift = shifts.find((entry) => entry.id === id);

  if (!shift) {
    return "not-found";
  }

  const names = await readMemberNames(scope, tenant);

  return {
    id: shift.id,
    startsAt: shift.startsAt.toString(),
    endsAt: shift.endsAt.toString(),
    status: shift.status,
    headcount: shift.headcount,
    breakMinutes: shift.breakMinutes,
    note: shift.note ?? null,
    requiredQualifications: shift.requiredQualifications,
    people: shift.assignments
      .filter((assignment) => assignment.status !== "released")
      .map((assignment) => ({
        id: assignment.id,
        userId: assignment.userId,
        name: names.get(assignment.userId) ?? assignment.userId,
        status: assignment.status,
      })),
  };
}

/**
 * One shift with who is on it. The block reads shifts by date range, so the
 * caller passes the days to search (`YYYY-MM-DD`).
 */
export function getShift(
  id: string,
  from: string,
  until: string,
): Promise<Loaded<ShiftDetailData | "not-found">> {
  return settle(() => loadShift(id, from, until));
}
