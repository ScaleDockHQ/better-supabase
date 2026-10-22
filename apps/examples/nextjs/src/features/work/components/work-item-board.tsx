"use client";

import type { WorkItemState } from "better-supabase/blocks/tasks";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";
import * as v from "valibot";

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

import type { StageColumn, WorkItemRow } from "../work-types";

import {
  stateBadgeVariant,
  usePriorityLabel,
  useStateLabel,
  useWorkErrorHint,
} from "../use-work-labels";
import { moveWorkItem } from "../work-actions";
import { WorkItemStateSchema } from "../work-types";

type Columns = Record<string, WorkItemRow[]>;

function columnsOf(
  stages: readonly StageColumn[],
  items: readonly WorkItemRow[],
): Columns {
  const columns: Columns = Object.fromEntries(
    stages.map((stage) => [stage.id, []]),
  );

  for (const item of items.toSorted((a, b) =>
    a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0,
  )) {
    if (item.stageId !== null) {
      columns[item.stageId]?.push(item);
    }
  }

  return columns;
}

function stateOf(category: string): WorkItemState | null {
  const parsed = v.safeParse(WorkItemStateSchema, category);

  return parsed.success ? parsed.output : null;
}

function WorkItemCard({ item }: { item: WorkItemRow }) {
  const t = useExtracted("work");
  const priorityLabel = usePriorityLabel();

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-2">
        <div className="flex flex-col gap-1">
          <span className="text-sm font-medium">{item.title}</span>
          <span className="text-xs text-muted-foreground tabular-nums">
            {item.identifier}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-1">
          {item.priority === 0 ? null : (
            <Badge variant={item.priority <= 2 ? "warning-light" : "outline"}>
              {priorityLabel(item.priority)}
            </Badge>
          )}
          {item.assigneeIds.length === 0 ? null : (
            <Badge variant="secondary">
              {t("{count, plural, one {# assignee} other {# assignees}}", {
                count: item.assigneeIds.length,
              })}
            </Badge>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

// #region recipe:work-item-board
/**
 * Work items in the columns of the workflow's stages, each column labelled with
 * the state its stage stands for. Dragging to another column changes the stage,
 * which the pipelines trigger checks against the allowed transitions; dragging
 * within a column saves the order through the rank block. A refused move puts
 * the card back. The parent keys it by the items' positions, so a server
 * refresh starts it from the saved board.
 */
export function WorkItemBoard({
  stages,
  items,
  canMove,
}: {
  stages: readonly StageColumn[];
  items: readonly WorkItemRow[];
  canMove: boolean;
}) {
  const t = useExtracted("work");
  const errorMessage = useErrorMessage();
  const stateLabel = useStateLabel();
  const workErrorHint = useWorkErrorHint();
  const [columns, setColumns] = useState(() => columnsOf(stages, items));
  const move = useAction(moveWorkItem);
  const byId = new Map(items.map((item) => [item.id, item]));

  return (
    <div data-recipe="work-item-board">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(item) => item.id}
        onValueCommit={(value, meta) => {
          if (meta.kind !== "item") {
            return;
          }

          const column = value[meta.overContainer] ?? [];
          const previous = column[meta.overIndex - 1];
          const next = column[meta.overIndex + 1];

          void move
            .run({
              id: String(meta.event.active.id),
              stageId: meta.overContainer,
              stageChanged: meta.activeContainer !== meta.overContainer,
              previousId: previous?.id ?? null,
              nextId: next?.id ?? null,
            })
            .then((result) => {
              if (!result.ok) {
                setColumns(meta.previousValue);
                toast.error(
                  workErrorHint(result.error.hint) ??
                    errorMessage(result.error),
                );

                return;
              }

              if (!result.data.ordered) {
                toast.warning(
                  t("Moved, but its place in the column wasn't saved."),
                );
              }
            });
        }}
      >
        <KanbanBoard className="flex overflow-x-auto">
          {stages.map((stage) => {
            const state = stateOf(stage.category);
            const count = columns[stage.id]?.length ?? 0;

            return (
              <KanbanColumn
                key={stage.id}
                value={stage.id}
                className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex min-w-0 flex-col gap-1">
                    <span className="truncate text-sm font-medium">
                      {stage.name}
                    </span>
                    {state === null ? null : (
                      <Badge variant={stateBadgeVariant(state)}>
                        {stateLabel(state)}
                      </Badge>
                    )}
                  </div>
                  <Badge
                    variant={
                      stage.wipLimit !== null && count > stage.wipLimit
                        ? "destructive-light"
                        : "outline"
                    }
                  >
                    {stage.wipLimit === null
                      ? count
                      : t("{count, number} of {limit, number}", {
                          count,
                          limit: stage.wipLimit,
                        })}
                  </Badge>
                </div>
                <KanbanColumnContent value={stage.id} className="min-h-16">
                  {(columns[stage.id] ?? []).map((item) => (
                    <KanbanItem
                      key={item.id}
                      value={item.id}
                      disabled={!canMove || move.pending}
                    >
                      <KanbanItemHandle cursor={canMove}>
                        <WorkItemCard item={item} />
                      </KanbanItemHandle>
                    </KanbanItem>
                  ))}
                  {count === 0 ? (
                    <p className="text-xs text-muted-foreground">
                      {t("Drop an item here.")}
                    </p>
                  ) : null}
                </KanbanColumnContent>
              </KanbanColumn>
            );
          })}
        </KanbanBoard>
        <KanbanOverlay>
          {({ value, variant }) => {
            const item =
              variant === "item" ? byId.get(String(value)) : undefined;

            return item ? <WorkItemCard item={item} /> : null;
          }}
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
// #endregion recipe:work-item-board
