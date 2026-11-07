import { io } from "next/cache";

import { getAppraisals } from "@/features/appraisals/appraisals-queries";
import { AppraisalList } from "@/features/appraisals/components/appraisal-list";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function AppraisalListSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <AppraisalList
      state={await getAppraisals()}
      canManage={can(permissions, "appraisals.manage")}
    />
  );
}
