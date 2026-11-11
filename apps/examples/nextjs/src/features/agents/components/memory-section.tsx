import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getMemory } from "../agents-queries";
import { MemoryManager } from "./memory-manager";

/** Render inside `<Suspense>`: core memory files and remembered facts. */
export async function MemorySection() {
  const [{ files, facts }, permissions] = await Promise.all([
    getMemory(),
    getPermissions(),
  ]);

  return (
    <MemoryManager
      files={files}
      facts={facts}
      canManage={can(permissions, "memory.manage")}
    />
  );
}

export function MemorySectionSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-2" aria-busy="true">
      <Skeleton className="h-64 w-full" />
      <Skeleton className="h-64 w-full" />
    </div>
  );
}
