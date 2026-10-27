"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import {
  Kanban,
  KanbanBoard,
  KanbanColumn,
  KanbanColumnContent,
  KanbanItem,
  KanbanItemHandle,
  KanbanOverlay,
} from "@/components/reui/kanban";
import { Card, CardContent } from "@/components/ui/card";
import { useErrorMessage } from "@/lib/use-error-message";

import type { MemberOption, TaskRow } from "../project-types";

import { moveTask } from "../project-actions";
import { TASK_STATUSES } from "../project-types";
import { statusBadgeVariant, useStatusLabel } from "../use-task-labels";

// #region recipe:record-board
type Columns = Record<string, TaskRow[]>;

/** One column per option of the select column; rows arrive in rank order. */
function columnsOf(rows: readonly TaskRow[]): Columns {
  const columns: Columns = Object.fromEntries(
    TASK_STATUSES.map((status) => [status, []]),
  );

  for (const row of rows) {
    columns[row.status]?.push(row);
  }

  return columns;
}

function TaskCard({
  task,
  assignee,
}: {
  task: TaskRow;
  assignee: string | null;
}) {
  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-2">
        <span className="text-sm font-medium">{task.title}</span>
        <div className="flex flex-wrap items-center gap-1">
          {task.dueOn === null ? null : (
            <Badge variant="outline">{task.dueOn}</Badge>
          )}
          {assignee === null ? null : (
            <Badge variant="secondary">{assignee}</Badge>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

/**
 * Tasks in a column per status. A drop calls `rank.move` with the cards on
 * either side and the column, so the status and the order save together. A
 * refused move puts the card back.
 */
export function TaskBoard({
  rows,
  members,
  canMove,
}: {
  rows: readonly TaskRow[];
  members: readonly MemberOption[];
  canMove: boolean;
}) {
  const t = useExtracted("projects");
  const errorMessage = useErrorMessage();
  const statusLabel = useStatusLabel();
  const [columns, setColumns] = useState(() => columnsOf(rows));
  const move = useAction(moveTask);
  const byId = new Map(rows.map((row) => [row.id, row]));
  const memberName = new Map(members.map((each) => [each.userId, each.name]));

  const assigneeOf = (task: TaskRow) =>
    task.assigneeId === null ? null : (memberName.get(task.assigneeId) ?? null);

  return (
    <div data-recipe="record-board">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(item) => item.id}
        onValueCommit={(value, meta) => {
          const status = TASK_STATUSES.find(
            (each) => each === meta.overContainer,
          );

          if (meta.kind !== "item" || status === undefined) {
            return;
          }

          const column = value[status] ?? [];

          void move
            .run({
              id: String(meta.event.active.id),
              status,
              previousId: column[meta.overIndex - 1]?.id ?? null,
              nextId: column[meta.overIndex + 1]?.id ?? null,
            })
            .then((result) => {
              if (!result.ok) {
                setColumns(meta.previousValue);
                toast.error(errorMessage(result.error));
              }

              return result;
            });
        }}
      >
        <KanbanBoard className="flex overflow-x-auto">
          {TASK_STATUSES.map((status) => {
            const tasks = columns[status] ?? [];

            return (
              <KanbanColumn
                key={status}
                value={status}
                className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <Badge variant={statusBadgeVariant(status)}>
                    {statusLabel(status)}
                  </Badge>
                  <Badge variant="outline">{tasks.length}</Badge>
                </div>
                <KanbanColumnContent value={status} className="min-h-16">
                  {tasks.map((task) => (
                    <KanbanItem
                      key={task.id}
                      value={task.id}
                      disabled={!canMove || move.pending}
                    >
                      <KanbanItemHandle cursor={canMove}>
                        <TaskCard task={task} assignee={assigneeOf(task)} />
                      </KanbanItemHandle>
                    </KanbanItem>
                  ))}
                  {tasks.length === 0 ? (
                    <p className="text-xs text-muted-foreground">
                      {t("Drop a task here.")}
                    </p>
                  ) : null}
                </KanbanColumnContent>
              </KanbanColumn>
            );
          })}
        </KanbanBoard>
        <KanbanOverlay>
          {({ value, variant }) => {
            const task =
              variant === "item" ? byId.get(String(value)) : undefined;

            return task ? (
              <TaskCard task={task} assignee={assigneeOf(task)} />
            ) : null;
          }}
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
// #endregion recipe:record-board
