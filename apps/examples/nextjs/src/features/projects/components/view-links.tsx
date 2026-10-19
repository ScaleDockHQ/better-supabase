"use client";

import {
  CalendarDaysIcon,
  CalendarRangeIcon,
  ChartGanttIcon,
  KanbanIcon,
  Table2Icon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import { buttonVariants } from "@/components/ui/button";
import { ButtonGroup } from "@/components/ui/button-group";
import { Link } from "@/i18n/navigation";

import { TASK_VIEWS, type TaskView } from "../project-types";
import { useViewLabel } from "../use-task-labels";

const ICONS = {
  table: Table2Icon,
  board: KanbanIcon,
  calendar: CalendarDaysIcon,
  timeline: CalendarRangeIcon,
  gantt: ChartGanttIcon,
} as const satisfies Record<TaskView, typeof Table2Icon>;

/** One link per screen over the same tasks, keeping search and filters. */
export function ViewLinks({
  active,
  hrefs,
}: {
  active: TaskView;
  hrefs: Readonly<Record<TaskView, string>>;
}) {
  const t = useExtracted("projects");
  const viewLabel = useViewLabel();

  return (
    <ButtonGroup aria-label={t("Screens")}>
      {TASK_VIEWS.map((view) => {
        const Icon = ICONS[view];
        const current = view === active;

        return (
          <Link
            key={view}
            href={hrefs[view]}
            aria-current={current ? "page" : undefined}
            className={buttonVariants({
              size: "sm",
              variant: current ? "secondary" : "outline",
            })}
          >
            <Icon />
            {viewLabel(view)}
          </Link>
        );
      })}
    </ButtonGroup>
  );
}
