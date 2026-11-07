import { io } from "next/cache";

import { Samples } from "@/features/lims/components/samples";
import { getSamples } from "@/features/lims/lims-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function SamplesSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Samples
      state={await getSamples()}
      canWrite={can(permissions, "lims.write")}
    />
  );
}
