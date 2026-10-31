import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  UsageRights,
  UsageRightsSkeleton,
} from "@/features/dam/components/usage-rights";
import { getUsageRights } from "@/features/dam/dam-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function Rights() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <UsageRights
      state={await getUsageRights()}
      canWrite={can(permissions, "dam.write")}
    />
  );
}

export default function DamPage() {
  const t = useExtracted("dam");

  return (
    <>
      <PageHeader
        title={t("Assets")}
        description={t("Who may use your files, where, and until when.")}
      />
      <Suspense fallback={<UsageRightsSkeleton />}>
        <PermissionGate permission="dam.read">
          <Rights />
        </PermissionGate>
      </Suspense>
    </>
  );
}
