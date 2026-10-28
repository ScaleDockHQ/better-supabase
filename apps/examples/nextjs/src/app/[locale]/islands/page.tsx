import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import { AuthzRefresh } from "@/features/islands/components/authz-refresh";
import {
  CacheStatus,
  CacheStatusSkeleton,
} from "@/features/islands/components/cache-status";
import {
  CountIsland,
  CountIslandSkeleton,
} from "@/features/islands/components/count-island";
import {
  SessionIsland,
  SessionIslandSkeleton,
} from "@/features/islands/components/session-island";
import { islandScope } from "@/features/islands/islands-queries";
import { Link } from "@/i18n/navigation";
import { bsb } from "@/lib/supabase/server";

// Everything above the islands is the static shell, so a prefetch of this
// page needs no session; the islands stream in behind their boundaries.
export const ensureStatic = "shell";

/**
 * Ten islands, one query. The page sits outside the `(app)` layout, whose
 * sidebar and menus make calls of their own, so a page load here is exactly one
 * token verification and one `bootstrap_islands` call. `?scope=remote` reads
 * the same data through `"use cache: remote"`.
 */
export default function IslandsPage({
  searchParams,
}: PageProps<"/[locale]/islands">) {
  const t = useExtracted("islands");
  const scope = searchParams.then((params) => islandScope(params["scope"]));

  return (
    <main className="mx-auto flex w-full max-w-6xl flex-col gap-8 p-4 md:p-6">
      <PageHeader
        title={t("Islands")}
        description={t("Ten islands that read one bootstrap call per request.")}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Link
              href="/"
              className={buttonVariants({ variant: "ghost", size: "sm" })}
            >
              {t("Dashboard")}
            </Link>
            <Suspense fallback={<CacheStatusSkeleton />}>
              <CacheStatus scope={scope} />
            </Suspense>
          </div>
        }
      />
      <Suspense fallback={null}>
        <IslandsAuthzRefresh />
      </Suspense>
      <section className="flex flex-col gap-4">
        <h2 className="text-sm font-medium text-muted-foreground">
          {t("Rows")}
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="customers" scope={scope} />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="notes" scope={scope} />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="contacts" scope={scope} />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="tags" scope={scope} />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="tasks" scope={scope} />
          </Suspense>
        </div>
      </section>
      <section className="flex flex-col gap-4">
        <h2 className="text-sm font-medium text-muted-foreground">
          {t("Session")}
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="email" scope={scope} />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="organization" scope={scope} />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="expires" scope={scope} />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="issued" scope={scope} />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="version" scope={scope} />
          </Suspense>
        </div>
      </section>
    </main>
  );
}

/** Starts the session read inside its boundary, so the shell never waits for it. */
function IslandsAuthzRefresh() {
  return <AuthzRefresh session={bsb.claims()} />;
}
