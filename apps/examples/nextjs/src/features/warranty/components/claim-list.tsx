import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getClaimFormOptions, getClaims } from "../warranty-queries";
import { ClaimRecordList } from "./claim-record-list";

/** Render inside `<Suspense>`; the fallback is `ClaimListSkeleton`. */
export async function ClaimList() {
  const [page, permissions, t] = await Promise.all([
    getClaims(),
    getPermissions(),
    getExtracted("warranty"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its claims.")}
      </p>
    );
  }

  const canWrite = can(permissions, "warranty.write");

  return (
    <ClaimRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canWrite={canWrite}
      options={canWrite ? await getClaimFormOptions() : null}
    />
  );
}

export function ClaimListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
