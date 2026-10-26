import type { CSSProperties } from "react";
import type { Temporal } from "temporal-polyfill";

import { getExtracted } from "next-intl/server";

import type { AppHref } from "@/i18n/navigation";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Link } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import type { MemberOption, TaskRow } from "../project-types";

import { spanOf } from "../task-dates";
import { WindowDays, WindowNav } from "./window-header";

// #region recipe:record-timeline
const UNASSIGNED = "";

/**
 * Tasks as bars from `startsOn` to `dueOn`, one lane per assignee, over a
 * four-week window that lives in the URL (`?from=YYYY-MM-DD`).
 */
export async function TaskTimeline({
  rows,
  members,
  from,
  today,
  windowHref,
}: {
  rows: readonly TaskRow[];
  members: readonly MemberOption[];
  from: Temporal.PlainDate;
  today: Temporal.PlainDate;
  windowHref: (from: string) => AppHref;
}) {
  const t = await getExtracted("projects");
  const lanes = new Map<string, TaskRow[]>();

  for (const row of rows) {
    if (spanOf(row, from) !== null) {
      const lane = row.assigneeId ?? UNASSIGNED;

      lanes.set(lane, [...(lanes.get(lane) ?? []), row]);
    }
  }

  const laneName = (id: string) =>
    id === UNASSIGNED
      ? t("Unassigned")
      : (members.find((member) => member.userId === id)?.name ?? id);

  return (
    <Card data-recipe="record-timeline">
      <CardHeader>
        <CardTitle>{t("Timeline")}</CardTitle>
        <CardDescription>
          {t(
            "Tasks with a start or due date in these four weeks, by assignee.",
          )}
        </CardDescription>
        <CardAction>
          <WindowNav from={from} today={today} windowHref={windowHref} />
        </CardAction>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <div className="min-w-[56rem] overflow-hidden rounded-lg border">
            <div className="grid grid-cols-[10rem_1fr]">
              <span className="border-e border-b bg-muted/50" />
              <WindowDays from={from} today={today} />
              {lanes.size === 0 ? (
                <p className="col-span-2 p-4 text-sm text-muted-foreground">
                  {t("No tasks fall in these weeks.")}
                </p>
              ) : null}
              {[...lanes].map(([lane, tasks]) => (
                <div key={lane} className="contents">
                  <span className="truncate border-e border-b p-2 text-sm font-medium">
                    {laneName(lane)}
                  </span>
                  <ol className="grid grid-cols-28 gap-y-1 border-b py-1.5">
                    {tasks.map((task) => {
                      const span = spanOf(task, from);

                      return span === null ? null : (
                        <li
                          key={task.id}
                          className="[grid-column:var(--span-start)/span_var(--span-length)]"
                          // SAFETY: React's CSSProperties has no custom properties; both are numbers.
                          style={
                            {
                              "--span-start": span.start + 1,
                              "--span-length": span.length,
                            } as CSSProperties
                          }
                        >
                          <Link
                            href={`/projects/${task.projectId}`}
                            title={task.title}
                            className={cn(
                              "block truncate rounded-sm bg-primary/10 px-1.5 py-0.5 text-xs transition-colors hover:bg-primary/20",
                              task.status === "done" &&
                                "text-muted-foreground line-through",
                            )}
                          >
                            {task.title}
                          </Link>
                        </li>
                      );
                    })}
                  </ol>
                </div>
              ))}
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
// #endregion recipe:record-timeline
