import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageBlockRows } from "@/lib/block-list";

import { deadlineList, deadlineSpec } from "../deadlines-list";
import { getDeadlines } from "../deadlines-queries";
import { DeadlineRecordList } from "./deadline-record-list";

/** Render inside `<Suspense>`: every computed deadline on the list kit. */
export async function DeadlineOverview() {
  const [t, permissions, deadlines] = await Promise.all([
    getExtracted("work"),
    getPermissions(),
    getDeadlines(),
  ]);

  if (!can(permissions, "deadlines.read")) {
    forbidden();
  }

  if (deadlines.kind === "no-organization") {
    return null;
  }

  if (deadlines.kind === "error") {
    return <PeopleLoadError title={t("Deadlines didn't load")} />;
  }

  return (
    <DeadlineRecordList
      initial={pageBlockRows(
        deadlineList,
        deadlineSpec,
        deadlines.data,
        deadlineList.defaults,
      )}
      kinds={[...new Set(deadlines.data.map((row) => row.kind))].toSorted()}
    />
  );
}

export function DeadlineOverviewSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
