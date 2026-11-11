import { Skeleton } from "@/components/ui/skeleton";
import { bsbCore } from "@/lib/supabase/server-core";

import type { ScopeVariant } from "../bench-cache";

import { readScope, readScopeFromHandle } from "../bench-queries";

/**
 * Render inside `<Suspense>`: one private scope of the benchmark page. The
 * `session` variant parks the session handle once per scope read.
 */
export async function ScopeIsland({
  index,
  variant,
}: {
  index: number;
  variant: Promise<ScopeVariant>;
}) {
  const session =
    (await variant) === "session" ? await bsbCore.sessionHandle() : undefined;

  const who = await (session
    ? readScopeFromHandle(index, session)
    : readScope(index));

  return (
    <li className="text-sm tabular-nums" data-testid={`scope-${index}`}>
      {who}
    </li>
  );
}

export function ScopeIslandSkeleton() {
  return <Skeleton className="h-5 w-full" aria-busy="true" />;
}
