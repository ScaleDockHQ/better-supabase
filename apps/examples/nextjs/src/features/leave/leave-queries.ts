import "server-only";
import type { LeaveBalance, LeaveType } from "better-supabase/blocks/leave";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { bsb } from "@/lib/supabase/server";

import type { LeaveRow } from "./leave-list";

import { LEAVE_TAG } from "./leave-cache";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * The requests the caller reads: everyone's with `leave.read`, else their own.
 * The block lists a bounded window and has no search of its own, so the list
 * kit searches, filters and pages these rows on the server (EX-901).
 */
export async function readLeaveRows(
  db: Db,
  organizationId: string,
): Promise<{
  readonly rows: readonly LeaveRow[];
  readonly types: readonly LeaveType[];
}> {
  const [types, all, chart] = await Promise.all([
    db.leave.types({ organizationId }),
    db.leave.list({ organizationId, everyone: true, pageSize: 500 }),
    db.employees.orgChart({ organizationId }),
  ]);

  const requests = all.ok
    ? all
    : await db.leave.list({ organizationId, pageSize: 500 });

  if (!types.ok || !requests.ok) {
    throw new Error("The leave requests did not load");
  }

  const typeById = new Map(types.data.map((type) => [type.id, type]));
  const nameByUser = new Map<string, string>();
  const nameByEmployee = new Map<string, string>();

  if (chart.ok) {
    for (const employee of chart.data) {
      nameByEmployee.set(employee.id, employee.name);

      if (employee.userId) {
        nameByUser.set(employee.userId, employee.name);
      }
    }
  }

  return {
    types: types.data,
    rows: requests.data.map((request): LeaveRow => {
      const type = typeById.get(request.typeId);

      return {
        id: request.id,
        who:
          (request.employeeId
            ? nameByEmployee.get(request.employeeId)
            : null) ??
          (request.userId ? nameByUser.get(request.userId) : null) ??
          "–",
        typeId: request.typeId,
        typeName: type?.name ?? "–",
        unit: type?.unit ?? "days",
        startsOn: request.startsOn.toString(),
        endsOn: request.endsOn.toString(),
        amount: request.amount,
        status: request.status,
        approvalId: request.approvalId ?? null,
        note: request.note ?? null,
      };
    }),
  };
}

export interface LeaveOverviewData {
  /** Plain fields only: a cached value cannot hold the block's Temporal dates. */
  readonly types: readonly { readonly id: string; readonly name: string }[];
  readonly balances: readonly LeaveBalance[];
  readonly rows: readonly LeaveRow[];
}

async function loadLeave(): Promise<LeaveOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(LEAVE_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [{ rows, types }, balances] = await Promise.all([
    readLeaveRows(db, organizationId),
    db.leave.balances({ organizationId }).orThrow(),
  ]);

  return { types: types.map(({ id, name }) => ({ id, name })), balances, rows };
}

export function getLeave(): Promise<Loaded<LeaveOverviewData>> {
  return settle(loadLeave);
}

export interface LeaveLedgerRow {
  readonly id: string;
  readonly kind: string;
  readonly amount: number;
  readonly createdAt: string;
  readonly note: string | null;
}

export type LeaveDetailData =
  | { readonly found: false }
  | {
      readonly found: true;
      readonly request: LeaveRow;
      readonly ledger: readonly LeaveLedgerRow[];
      readonly available: number | null;
    };

async function loadLeaveRequest(id: string): Promise<LeaveDetailData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(LEAVE_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const { rows } = await readLeaveRows(db, organizationId);
  const request = rows.find((row) => row.id === id);

  if (!request) {
    return { found: false };
  }

  const [ledger, balances] = await Promise.all([
    db.leave.ledger({ organizationId, typeId: request.typeId }),
    db.leave.balances({ organizationId }),
  ]);

  return {
    found: true,
    request,
    ledger: ledger.ok
      ? ledger.data
          .filter((entry) => entry.requestId === id)
          .map((entry) => ({
            id: entry.id,
            kind: entry.kind,
            amount: entry.amount,
            createdAt: entry.createdAt.toString(),
            note: entry.note ?? null,
          }))
      : [],
    available: balances.ok
      ? (balances.data.find((balance) => balance.typeId === request.typeId)
          ?.available ?? null)
      : null,
  };
}

/** One request with the ledger entries that booked it. */
export function getLeaveRequest(id: string): Promise<Loaded<LeaveDetailData>> {
  return settle(() => loadLeaveRequest(id));
}
