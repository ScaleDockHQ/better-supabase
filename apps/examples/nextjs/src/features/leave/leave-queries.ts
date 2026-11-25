import "server-only";
import type {
  LeaveBalance,
  LeaveRequest,
  LeaveType,
} from "better-supabase/blocks/leave";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";

import type { LeaveRow } from "./leave-list";

import { LEAVE_TAG } from "./leave-cache";
import { leaveList, leaveMap } from "./leave-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** Who and what a request row names: the leave types and the people. */
interface LeaveNames {
  readonly types: readonly LeaveType[];
  readonly nameByUser: ReadonlyMap<string, string>;
  readonly nameByEmployee: ReadonlyMap<string, string>;
}

async function getLeaveNames(
  db: Db,
  organizationId: string,
): Promise<LeaveNames> {
  const [types, chart] = await Promise.all([
    db.leave.types({ organizationId }),
    db.employees.orgChart({ organizationId }),
  ]);

  if (!types.ok) {
    throw new Error("The leave requests did not load");
  }

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

  return { types: types.data, nameByUser, nameByEmployee };
}

function leaveRowOf(request: LeaveRequest, names: LeaveNames): LeaveRow {
  const type = names.types.find((entry) => entry.id === request.typeId);

  return {
    id: request.id,
    who:
      (request.employeeId
        ? names.nameByEmployee.get(request.employeeId)
        : null) ??
      (request.userId ? names.nameByUser.get(request.userId) : null) ??
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
}

/**
 * One page of the requests the caller reads, with the leave block's page and
 * facet methods: everyone's with `leave.read`, else their own.
 */
export async function getLeavePage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
  known?: LeaveNames,
): Promise<{
  readonly page: RecordListPage<LeaveRow>;
  readonly types: readonly LeaveType[];
}> {
  const { leave } = db;

  const [names, everyone] = await Promise.all([
    known ?? getLeaveNames(db, organizationId),
    leave.requestCount({ organizationId, filters: { everyone: ["true"] } }),
  ]);

  const scope = everyone.ok ? { everyone: ["true"] } : {};

  const page = await pageEntityRows({
    pager: {
      page: (options) =>
        leave.requestPage({
          organizationId,
          ...options,
          filters: { ...options.filters, ...scope },
        }),
      facets: (options) =>
        leave.requestFacets({
          organizationId,
          ...options,
          filters: { ...options.filters, ...scope },
        }),
    },
    map: leaveMap,
    query,
    pageSize: leaveList.config.pageSize,
    rowsOf: (items) => items.map((request) => leaveRowOf(request, names)),
  });

  return { page, types: names.types };
}

export interface LeaveOverviewData {
  /** Plain fields only: a cached value cannot hold the block's Temporal dates. */
  readonly types: readonly { readonly id: string; readonly name: string }[];
  readonly balances: readonly LeaveBalance[];
  readonly initial: RecordListPage<LeaveRow>;
}

async function loadLeave(): Promise<LeaveOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(LEAVE_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [{ page, types }, balances] = await Promise.all([
    getLeavePage(db, organizationId, leaveList.defaults),
    db.leave.balances({ organizationId }).orThrow(),
  ]);

  return {
    types: types.map(({ id, name }) => ({ id, name })),
    balances,
    initial: page,
  };
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

  const found = await db.leave.getRequest(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return { found: false };
    }

    throw new Error(found.error.message);
  }

  const request = leaveRowOf(
    found.data,
    await getLeaveNames(db, organizationId),
  );

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
