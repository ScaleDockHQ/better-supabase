import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getPasses } from "../passes-queries";
import { PassRecordList } from "./pass-record-list";

/** Render inside `<Suspense>`; the fallback is `PassListSkeleton`. */
export async function PassList() {
  const [page, permissions, t] = await Promise.all([
    getPasses(),
    getPermissions(),
    getExtracted("passes"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its passes.")}
      </p>
    );
  }

  return (
    <PassRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canManage={can(permissions, "passes.manage")}
    />
  );
}

export function PassListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
