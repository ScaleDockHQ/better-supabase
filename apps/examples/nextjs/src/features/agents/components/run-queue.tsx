import { getExtracted } from "next-intl/server";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { getRunPage, RUN_WINDOW } from "../agents-queries";
import { RunTable } from "./run-table";

const GROUPS = ["queued", "running", "failed", "completed"] as const;

/**
 * Render inside `<Suspense>`: a count per state (each links to its filter) over
 * the filtered runs for the URL's state.
 */
export async function RunQueue({ query }: { query: Promise<OpsListQuery> }) {
  const [page, t] = await Promise.all([
    query.then(getRunPage),
    getExtracted("agents"),
  ]);

  const labels = {
    queued: t("Queued"),
    running: t("Running"),
    failed: t("Failed"),
    completed: t("Completed"),
  } as const;

  return (
    <div className="flex flex-col gap-4">
      <ul className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {GROUPS.map((state) => (
          <li key={state}>
            <Link
              href={`/assistant/agents/runs?filter=${state}`}
              className="block transition-colors hover:opacity-80"
            >
              <Card size="sm">
                <CardContent className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">
                    {labels[state]}
                  </span>
                  <span className="text-xl font-semibold tabular-nums">
                    {page.counts[state]}
                    {page.capped ? "+" : ""}
                  </span>
                </CardContent>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
      {page.capped ? (
        <Badge variant="info-light">
          {t("Counts cover the newest {count, number} runs.", {
            count: RUN_WINDOW,
          })}
        </Badge>
      ) : null}
      <RunTable items={page.items} nextCursor={page.nextCursor} />
    </div>
  );
}

export function RunQueueSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {GROUPS.map((state) => (
          <Skeleton key={state} className="h-16 w-full" />
        ))}
      </div>
      <RecordListSkeleton rows={5} />
    </div>
  );
}
