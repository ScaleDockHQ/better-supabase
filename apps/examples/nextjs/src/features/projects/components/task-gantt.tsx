import type { CSSProperties } from "react";
import type { Temporal } from "temporal-polyfill";

import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Link } from "@/i18n/navigation";

import type { ProjectOption, TaskRow, TaskStatus } from "../project-types";

import { spanOf } from "../task-dates";
import { WindowDays, WindowNav } from "./window-header";

// #region recipe:record-gantt
const BAR = {
  todo: "bg-muted-foreground/30",
  doing: "bg-primary/60",
  done: "bg-primary/25",
} as const satisfies Record<TaskStatus, string>;

/**
 * One row per task under its project, with a bar from `startsOn` to `dueOn`.
 * Tasks without dates stay in the list with an empty track, so the plan
 * shows what still needs scheduling.
 */
export async function TaskGantt({
  rows,
  projects,
  from,
  today,
  windowHref,
}: {
  rows: readonly TaskRow[];
  projects: readonly ProjectOption[];
  from: Temporal.PlainDate;
  today: Temporal.PlainDate;
  windowHref: (from: string) => string;
}) {
  const t = await getExtracted("projects");

  const groups = projects
    .map((project) => ({
      project,
      tasks: rows.filter((row) => row.projectId === project.id),
    }))
    .filter((group) => group.tasks.length > 0);

  return (
    <Card data-recipe="record-gantt">
      <CardHeader>
        <CardTitle>{t("Gantt")}</CardTitle>
        <CardDescription>
          {t("Every task by project, with its planned dates.")}
        </CardDescription>
        <CardAction>
          <WindowNav from={from} today={today} windowHref={windowHref} />
        </CardAction>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <div className="min-w-[60rem] overflow-hidden rounded-lg border">
            <div className="grid grid-cols-[14rem_1fr]">
              <span className="border-e border-b bg-muted/50" />
              <WindowDays from={from} today={today} />
              {groups.map(({ project, tasks }) => (
                <div key={project.id} className="contents">
                  <Link
                    href={`/projects/${project.id}`}
                    className="col-span-2 border-b bg-muted/30 px-2 py-1.5 text-sm font-medium hover:underline"
                  >
                    {project.name}
                  </Link>
                  {tasks.map((task) => {
                    const span = spanOf(task, from);

                    return (
                      <div key={task.id} className="contents">
                        <span className="flex items-center justify-between gap-2 border-e border-b px-2 py-1.5 ps-4">
                          <span className="truncate text-sm">{task.title}</span>
                          {span === null &&
                          task.startsOn === null &&
                          task.dueOn === null ? (
                            <Badge variant="outline">{t("No dates")}</Badge>
                          ) : null}
                        </span>
                        <div className="grid grid-cols-28 items-center border-b">
                          {span === null ? null : (
                            <span
                              title={t("{start} to {end}", {
                                start: task.startsOn ?? task.dueOn ?? "",
                                end: task.dueOn ?? task.startsOn ?? "",
                              })}
                              className={`[grid-column:var(--span-start)/span_var(--span-length)] h-4 rounded-sm ${BAR[task.status]}`}
                              // SAFETY: React's CSSProperties has no custom properties; both are numbers.
                              style={
                                {
                                  "--span-start": span.start + 1,
                                  "--span-length": span.length,
                                } as CSSProperties
                              }
                            />
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
// #endregion recipe:record-gantt
