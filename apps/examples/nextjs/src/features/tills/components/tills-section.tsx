import { io } from "next/cache";

import { Tills } from "@/features/tills/components/tills";
import { getTillSessions } from "@/features/tills/tills-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function TillsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Tills
      state={await getTillSessions()}
      canManage={can(permissions, "tills.manage")}
    />
  );
}
