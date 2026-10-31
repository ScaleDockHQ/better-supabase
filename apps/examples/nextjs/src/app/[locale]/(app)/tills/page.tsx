import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { Tills, TillsSkeleton } from "@/features/tills/components/tills";
import { getTillSessions } from "@/features/tills/tills-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function SessionList() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <Tills
      state={await getTillSessions()}
      canManage={can(permissions, "tills.manage")}
    />
  );
}

export default function TillsPage() {
  const t = useExtracted("tills");

  return (
    <>
      <PageHeader
        title={t("Tills")}
        description={t(
          "Cash drawer shifts with their expected cash and status.",
        )}
      />
      <Suspense fallback={<TillsSkeleton />}>
        <PermissionGate permission="tills.read">
          <SessionList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
