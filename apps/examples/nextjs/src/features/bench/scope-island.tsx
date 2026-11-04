import type { SessionHandle } from "better-supabase/next";

import { Skeleton } from "@/components/ui/skeleton";

import { readScope, readScopeFromHandle } from "./scope-queries";

/** Render inside `<Suspense>`: one private scope of the benchmark page. */
export async function ScopeIsland({
  index,
  session,
}: {
  index: number;
  session: SessionHandle | undefined;
}) {
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
