import type { LeaveBalance } from "better-supabase/blocks/leave";

import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { leaveList, leaveSpec } from "../leave-list";
import { getLeave } from "../leave-queries";
import { LeaveRecordList } from "./leave-record-list";
import { RequestLeaveDialog } from "./request-leave-dialog";
import { SetUpLeaveButton } from "./set-up-leave-button";

function BalanceCard({ balance }: { balance: LeaveBalance }) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {balance.name}
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-1">
        <span className="text-2xl font-semibold tabular-nums">
          {balance.available}
        </span>
        <span className="text-xs text-muted-foreground">
          {balance.taken} / {balance.granted} {balance.unit}
          {balance.pending > 0 ? ` (${balance.pending} pending)` : ""}
        </span>
      </CardContent>
    </Card>
  );
}

/**
 * Render inside `<Suspense>`: my balances as a KPI rail, then every request I
 * may read on the list kit. A manager with no leave types sees the set-up
 * action.
 */
export async function LeaveOverview() {
  const [t, permissions, leave] = await Promise.all([
    getExtracted("people"),
    getPermissions(),
    getLeave(),
  ]);

  if (!can(permissions, "leave.request") && !can(permissions, "leave.read")) {
    forbidden();
  }

  if (leave.kind === "no-organization") {
    return null;
  }

  if (leave.kind === "error") {
    return <PeopleLoadError title={t("Leave didn't load")} />;
  }

  const { rows, types, balances } = leave.data;
  const manager = can(permissions, "leave.manage");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-end gap-2">
        {manager && types.length === 0 ? <SetUpLeaveButton /> : null}
        {can(permissions, "leave.request") ? (
          <RequestLeaveDialog types={types} />
        ) : null}
      </div>
      {balances.length > 0 ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {balances.map((balance) => (
            <BalanceCard key={balance.typeId} balance={balance} />
          ))}
        </div>
      ) : null}
      <LeaveRecordList
        initial={pageBlockRows(leaveList, leaveSpec, rows, leaveList.defaults)}
        types={types.map((type) => ({ id: type.id, name: type.name }))}
      />
    </div>
  );
}

export function LeaveOverviewSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Skeleton className="h-24 rounded-xl" />
        <Skeleton className="h-24 rounded-xl" />
      </div>
      <RecordListSkeleton rows={5} />
    </div>
  );
}
