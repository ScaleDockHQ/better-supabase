import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getLeaseFormOptions, getLeases } from "../leases-queries";
import { LeaseRecordList } from "./lease-record-list";

/** Render inside `<Suspense>`; the fallback is `LeaseListSkeleton`. */
export async function LeaseList() {
  const [page, permissions, t] = await Promise.all([
    getLeases(),
    getPermissions(),
    getExtracted("leases"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its leases.")}
      </p>
    );
  }

  const canManage = can(permissions, "leases.manage");

  return (
    <LeaseRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canManage={canManage}
      options={canManage ? await getLeaseFormOptions() : null}
    />
  );
}

export function LeaseListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
