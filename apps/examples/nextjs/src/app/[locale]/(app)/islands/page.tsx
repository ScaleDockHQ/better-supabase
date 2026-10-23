import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CountIsland,
  CountIslandSkeleton,
} from "@/features/islands/components/count-island";
import {
  SessionIsland,
  SessionIslandSkeleton,
} from "@/features/islands/components/session-island";

export const instant = true;

/**
 * Ten private islands. The header is the static shell; each island streams in
 * its own `<Suspense>` boundary and checks the session itself.
 */
export default function IslandsPage() {
  const t = useExtracted("islands");

  return (
    <>
      <PageHeader
        title={t("Islands")}
        description={t(
          "Ten private islands that share one verified session per request.",
        )}
      />
      <section className="flex flex-col gap-4">
        <h2 className="text-sm font-medium text-muted-foreground">
          {t("Rows")}
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="customers" />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="notes" />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="contacts" />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="tags" />
          </Suspense>
          <Suspense fallback={<CountIslandSkeleton />}>
            <CountIsland table="tasks" />
          </Suspense>
        </div>
      </section>
      <section className="flex flex-col gap-4">
        <h2 className="text-sm font-medium text-muted-foreground">
          {t("Session")}
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="email" />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="organization" />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="expires" />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="issued" />
          </Suspense>
          <Suspense fallback={<SessionIslandSkeleton />}>
            <SessionIsland fact="version" />
          </Suspense>
        </div>
      </section>
    </>
  );
}
