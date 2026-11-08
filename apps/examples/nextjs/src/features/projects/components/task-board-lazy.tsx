"use client";

import type { ComponentProps } from "react";

import { lazy, Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";

const TaskBoard = lazy(() =>
  import("./task-board").then((mod) => ({ default: mod.TaskBoard })),
);

/**
 * The board view. The kanban and drag-and-drop code loads only when the URL's
 * view is the board, so the table, calendar, timeline and Gantt views never
 * download it.
 */
export function TaskBoardLazy(props: ComponentProps<typeof TaskBoard>) {
  return (
    <Suspense fallback={<Skeleton className="h-96 w-full rounded-xl" />}>
      <TaskBoard {...props} />
    </Suspense>
  );
}
