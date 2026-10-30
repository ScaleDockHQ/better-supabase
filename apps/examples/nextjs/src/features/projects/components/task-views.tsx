import { tenantOf } from "better-supabase/next";
import { ListTodoIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { connection } from "next/server";
import { Temporal } from "temporal-polyfill";

import type { AppHref } from "@/i18n/navigation";

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
import { Link, toSearch, withSearch } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import {
  getMemberOptions,
  getProjectOptions,
  getTasks,
  getTaskViews,
  settle,
} from "../project-queries";
import { parseTaskQuery, taskSearch } from "../project-types";
import { firstOfMonth, windowStart } from "../task-dates";
import { ProjectFormDialog } from "./project-form-dialog";
import { ProjectLoadError } from "./project-load-error";
import { TaskBoard } from "./task-board";
import { TaskCalendar } from "./task-calendar";
import { TaskFormDialog } from "./task-form-dialog";
import { TaskGantt } from "./task-gantt";
import { TaskGrid, TaskToolbar } from "./task-grid";
import { TaskTimeline } from "./task-timeline";
import { ViewLinks } from "./view-links";

/**
 * Render inside `<Suspense>`: the tasks for the URL's screen, search and
 * filters, with the toolbar every screen shares.
 */
export async function TaskViews({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, t, params, permissions] = await Promise.all([
    getSession(),
    getExtracted("projects"),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const query = parseTaskQuery(params);
  const canSaveViews = can(permissions, "saved_views.read");

  const [tasks, projects, members, views] = await Promise.all([
    settle(() => getTasks(query)),
    settle(getProjectOptions),
    settle(() => getMemberOptions(tenant)),
    canSaveViews
      ? settle(getTaskViews)
      : Promise.resolve({ kind: "ok" as const, data: [] }),
  ]);

  if (tasks.kind === "no-organization") {
    return null;
  }

  if (
    tasks.kind === "error" ||
    projects.kind !== "ok" ||
    members.kind !== "ok"
  ) {
    return <ProjectLoadError title={t("The tasks didn't load")} />;
  }

  const today = Temporal.Now.plainDateISO("UTC");

  const hrefWith = (key: string, value: string): AppHref => {
    const next = new URLSearchParams(taskSearch(query));

    next.set(key, value);

    return withSearch("/projects", toSearch(next));
  };

  const filtered =
    query.q !== "" || query.status !== null || query.projectId !== null;

  const view = (() => {
    switch (query.view) {
      case "table": {
        return (
          <Card>
            <CardContent>
              <TaskGrid
                key={taskSearch(query)}
                rows={tasks.data}
                projects={projects.data}
                members={members.data}
                canWrite
              />
            </CardContent>
          </Card>
        );
      }

      case "board": {
        return (
          <TaskBoard
            key={tasks.data
              .map((task) => `${task.id}:${task.status}`)
              .join(",")}
            rows={tasks.data}
            members={members.data}
            canMove
          />
        );
      }

      case "calendar": {
        return (
          <TaskCalendar
            rows={tasks.data}
            first={firstOfMonth(params["month"], today)}
            today={today}
            monthHref={(month) => hrefWith("month", month)}
          />
        );
      }

      case "timeline": {
        return (
          <TaskTimeline
            rows={tasks.data}
            members={members.data}
            from={windowStart(params["from"], today)}
            today={today}
            windowHref={(from) => hrefWith("from", from)}
          />
        );
      }

      case "gantt": {
        return (
          <TaskGantt
            rows={tasks.data}
            projects={projects.data}
            from={windowStart(params["from"], today)}
            today={today}
            windowHref={(from) => hrefWith("from", from)}
          />
        );
      }

      default: {
        const unknown: never = query.view;

        return unknown;
      }
    }
  })();

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <ViewLinks
          active={query.view}
          hrefs={{
            table: `/projects${taskSearch({ ...query, view: "table" })}`,
            board: `/projects${taskSearch({ ...query, view: "board" })}`,
            calendar: `/projects${taskSearch({ ...query, view: "calendar" })}`,
            timeline: `/projects${taskSearch({ ...query, view: "timeline" })}`,
            gantt: `/projects${taskSearch({ ...query, view: "gantt" })}`,
          }}
        />
        <div className="ml-auto flex items-center gap-2">
          <ProjectFormDialog />
          {projects.data.length === 0 ? null : (
            <TaskFormDialog
              projects={projects.data}
              members={members.data}
              defaultProjectId={query.projectId}
            />
          )}
        </div>
      </div>
      {views.kind === "error" ? (
        <ProjectLoadError title={t("The saved views didn't load")} />
      ) : null}
      <TaskToolbar
        query={query}
        projects={projects.data}
        views={views.kind === "ok" ? views.data : []}
        canSaveViews={canSaveViews}
      />
      {tasks.data.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <ListTodoIcon />
            </EmptyMedia>
            <EmptyTitle>
              {filtered ? t("No tasks match") : t("No tasks yet")}
            </EmptyTitle>
            <EmptyDescription>
              {filtered
                ? t("Change the search or the filters.")
                : projects.data.length === 0
                  ? t("Create a project first, then add its tasks.")
                  : t("Add the first task to a project.")}
            </EmptyDescription>
          </EmptyHeader>
          {!filtered && projects.data.length === 0 ? (
            <EmptyContent>
              <ProjectFormDialog variant="default" />
            </EmptyContent>
          ) : null}
          {!filtered && projects.data.length > 0 ? (
            <EmptyContent>
              <TaskFormDialog
                projects={projects.data}
                members={members.data}
                defaultProjectId={query.projectId}
              />
            </EmptyContent>
          ) : null}
          {filtered ? (
            <EmptyContent>
              <Link
                href={`/projects${taskSearch({ view: query.view, q: "", status: null, projectId: null })}`}
                className={cn(
                  buttonVariants({ size: "sm", variant: "outline" }),
                )}
              >
                {t("Clear filters")}
              </Link>
            </EmptyContent>
          ) : null}
        </Empty>
      ) : (
        view
      )}
    </div>
  );
}

export function TaskViewsSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <Skeleton className="h-8 w-80" />
      <Skeleton className="h-8 w-full" />
      <Skeleton className="h-96 rounded-xl" />
    </div>
  );
}
