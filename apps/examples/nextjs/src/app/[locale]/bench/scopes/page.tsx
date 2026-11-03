import { Suspense } from "react";

import {
  ScopeIsland,
  ScopeIslandSkeleton,
} from "@/features/bench/scope-island";
import { SCOPE_COUNT, scopeVariant } from "@/features/bench/scope-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * Twelve private cache scopes under one page. `?variant=session` parks the
 * session once and hands every scope the handle; the default has each scope
 * read the request. `tests/bench-scopes.spec.ts` counts the memo lookups.
 */
export default function ScopesBenchPage({
  searchParams,
}: PageProps<"/[locale]/bench/scopes">) {
  const variant = searchParams.then((params) =>
    scopeVariant(params["variant"]),
  );

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4 md:p-6">
      <h1 className="text-lg font-semibold">Private scopes</h1>
      <ul className="flex flex-col gap-2">
        {Array.from({ length: SCOPE_COUNT }, (_, index) => (
          <Suspense key={index} fallback={<ScopeIslandSkeleton />}>
            <Scope index={index} variant={variant} />
          </Suspense>
        ))}
      </ul>
    </main>
  );
}

async function Scope({
  index,
  variant,
}: {
  index: number;
  variant: Promise<"plain" | "session">;
}) {
  const session =
    (await variant) === "session" ? await bsb.sessionHandle() : undefined;

  return <ScopeIsland index={index} session={session} />;
}
