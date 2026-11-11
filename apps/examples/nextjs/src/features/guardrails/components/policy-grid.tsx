import { Skeleton } from "@/components/ui/skeleton";

import { getPolicyCards } from "../guardrails-queries";
import { PolicyCard } from "./policy-card";

/** Render inside `<Suspense>`: the effective policy of each agent and stage. */
export async function PolicyGrid() {
  const policies = await getPolicyCards();

  return (
    <ul className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {policies.map((policy) => (
        <li key={policy.id}>
          <PolicyCard policy={policy} />
        </li>
      ))}
    </ul>
  );
}

export function PolicyGridSkeleton() {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-busy="true">
      <Skeleton className="h-32 w-full" />
      <Skeleton className="h-32 w-full" />
      <Skeleton className="h-32 w-full" />
    </div>
  );
}
