import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { DataProviders } from "@/app/data-providers";
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
import { islandScope } from "@/features/islands/islands-cache";
import { liveCoreAuthzVersion } from "@/features/islands/live-version";
import { Link } from "@/i18n/navigation";
import { bsbCore } from "@/lib/supabase/server-core";

// Everything above the islands is the static shell, so a prefetch of this
// page needs no session; the islands stream in behind their boundaries.
export const ensureStatic = "shell";

/**
 * Ten islands, one query. The page sits outside the `(app)` layout, whose
 * sidebar and menus make calls of their own. A cold load is one token
 * verification and one `bootstrap_islands` call; a warm kept entry makes no
 * bootstrap call. The page still reads the live authorization version once, so
 * the client can skip its catch-up call. `?scope=remote` reads the same data
 * through `"use cache: remote"`.
 */
export default function IslandsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("islands");
  // oxlint-disable-next-line react-doctor/nextjs-async-dynamic-api-not-awaited -- mapped with then and passed on unawaited, so the page renders without waiting for the request.
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
async function IslandsAuthzRefresh() {
  const session = bsbCore.claims();
  const liveVersion = await liveCoreAuthzVersion();

  return (
    <DataProviders>
      <AuthzRefresh session={session} liveVersion={liveVersion} />
    </DataProviders>
  );
}
