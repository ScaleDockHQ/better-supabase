"use client";

import type { ComponentProps } from "react";

import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const TaskFormDialog = lazy(() =>
  import("./task-form-dialog").then((mod) => ({ default: mod.TaskFormDialog })),
);

/**
 * The "New task" button. The form, its project and assignee comboboxes and the
 * status select load on the first hover, focus or click.
 */
export function TaskFormDialogLazy(
  props: ComponentProps<typeof TaskFormDialog>,
) {
  const t = useExtracted("projects");

  return (
    <LazyOnIntent
      renderTrigger={(handlers) => (
        <Button size="sm" aria-haspopup="dialog" {...handlers}>
          <PlusIcon />
          {t("New task")}
        </Button>
      )}
    >
      <TaskFormDialog {...props} />
    </LazyOnIntent>
  );
}
