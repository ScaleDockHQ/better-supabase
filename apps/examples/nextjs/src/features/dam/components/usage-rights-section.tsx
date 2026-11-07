import { io } from "next/cache";

import { UsageRights } from "@/features/dam/components/usage-rights";
import { getUsageRights } from "@/features/dam/dam-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function UsageRightsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <UsageRights
      state={await getUsageRights()}
      canWrite={can(permissions, "dam.write")}
    />
  );
}
