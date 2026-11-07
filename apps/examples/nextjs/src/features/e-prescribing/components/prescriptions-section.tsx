import { io } from "next/cache";

import { Prescriptions } from "@/features/e-prescribing/components/prescriptions";
import { getPrescriptions } from "@/features/e-prescribing/e-prescribing-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function PrescriptionsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Prescriptions
      state={await getPrescriptions()}
      canSign={can(permissions, "e_prescribing.sign")}
      canCancel={can(permissions, "e_prescribing.write")}
    />
  );
}
