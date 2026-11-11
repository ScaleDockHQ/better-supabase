import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getDomains } from "../domains-queries";
import { AddDomainDialog } from "./domain-controls";
import { DomainRecordList } from "./domain-record-list";

/** Render inside `<Suspense>`; the fallback is `DomainListSkeleton`. */
export async function DomainList() {
  const [page, permissions] = await Promise.all([
    getDomains(),
    getPermissions(),
  ]);

  if (!page) {
    forbidden();
  }

  const manage = can(permissions, "domains.manage");

  return (
    <div className="flex flex-col gap-4">
      {manage ? (
        <div className="flex justify-end">
          <AddDomainDialog />
        </div>
      ) : null}
      <DomainRecordList initial={page} canManage={manage} />
    </div>
  );
}

export function DomainListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
