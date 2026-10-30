import { tenantOf } from "better-supabase/next";
import { ListTodoIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import {
  getAssignees,
  getWorkGrid,
  getWorkViews,
  settle,
} from "../work-queries";
import { parseWorkGridQuery } from "../work-types";
import { WorkItemGrid } from "./work-item-grid";
import { WorkLoadError } from "./work-load-error";

/**
 * Render inside `<Suspense>`: the work items for the URL's search, state filter
 * and sort, with the caller's saved views of the grid.
 */
export async function WorkGrid({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, t, params, permissions] = await Promise.all([
    getSession(),
    getExtracted("work"),
    searchParams,
    getPermissions(),
  ]);

  if (!can(permissions, "tasks.read")) {
    forbidden();
  }

  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const query = parseWorkGridQuery(params);

  const [grid, views, members] = await Promise.all([
    settle(() => getWorkGrid(query)),
    can(permissions, "saved_views.read")
      ? settle(getWorkViews)
      : Promise.resolve({ kind: "ok" as const, data: [] }),
    settle(() => getAssignees(tenant)),
  ]);

  if (grid.kind === "no-organization") {
    return null;
  }

  if (grid.kind === "error" || members.kind === "error") {
    return <WorkLoadError title={t("The work items didn't load")} />;
  }

  const filtered = query.q !== "" || query.state !== null;

  return (
    <div className="flex flex-col gap-4">
      {views.kind === "error" ? (
        <WorkLoadError title={t("The saved views didn't load")} />
      ) : null}
      <Card>
        <CardContent>
          {grid.data.rows.length === 0 && !filtered ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <ListTodoIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No work items yet")}</EmptyTitle>
                <EmptyDescription>
                  {t(
                    "Create items on the board, then sort and edit them here.",
                  )}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Link href="/work" className={buttonVariants({ size: "sm" })}>
                  {t("Open the board")}
                </Link>
              </EmptyContent>
            </Empty>
          ) : (
            <div className="flex flex-col gap-4">
              <WorkItemGrid
                key={JSON.stringify(query)}
                rows={grid.data.rows}
                stages={grid.data.stages}
                members={members.kind === "ok" ? members.data : []}
                views={views.kind === "ok" ? views.data : []}
                query={query}
                canWrite={can(permissions, "tasks.write")}
                canBulk={can(permissions, "bulk.run")}
              />
              {grid.data.rows.length === 0 ? (
                <Empty className="border">
                  <EmptyHeader>
                    <EmptyTitle>{t("No items match")}</EmptyTitle>
                    <EmptyDescription>
                      {t("Change the search or the state filter.")}
                    </EmptyDescription>
                  </EmptyHeader>
                  <EmptyContent>
                    <Link
                      href="/work/grid"
                      className={buttonVariants({
                        size: "sm",
                        variant: "outline",
                      })}
                    >
                      {t("Clear filters")}
                    </Link>
                  </EmptyContent>
                </Empty>
              ) : null}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function WorkGridSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <Skeleton className="h-8 w-full" />
      <Skeleton className="h-96 rounded-xl" />
    </div>
  );
}
