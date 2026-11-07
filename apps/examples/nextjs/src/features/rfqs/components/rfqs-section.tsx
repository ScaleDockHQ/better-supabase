import { io } from "next/cache";

import { Rfqs } from "@/features/rfqs/components/rfqs";
import { getRfqs } from "@/features/rfqs/rfqs-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function RfqsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Rfqs state={await getRfqs()} canWrite={can(permissions, "rfqs.write")} />
  );
}
