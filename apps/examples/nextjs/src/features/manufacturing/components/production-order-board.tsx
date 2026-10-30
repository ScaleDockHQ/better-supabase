"use client";

import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";
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

import type { ProductionOrderCard } from "../manufacturing-queries";
import type { BoardStatus } from "../production-order-statuses";

import {
  completeProductionOrder,
  releaseProductionOrder,
} from "../manufacturing-actions";
import { BOARD_STATUSES } from "../production-order-statuses";

type Columns = Record<string, ProductionOrderCard[]>;

const StatusSchema = v.picklist(BOARD_STATUSES);

function columnsOf(cards: readonly ProductionOrderCard[]): Columns {
  const columns: Columns = Object.fromEntries(
    BOARD_STATUSES.map((status) => [status, []]),
  );

  for (const card of cards) {
    columns[card.status]?.push(card);
  }

  return columns;
}

function useStatusLabel(): (status: BoardStatus) => string {
  const t = useExtracted("manufacturing");

  return (status) => {
    switch (status) {
      case "draft": {
        return t("Draft");
      }

      case "released": {
        return t("Released");
      }

      case "in_progress": {
        return t("In progress");
      }

      case "done": {
        return t("Done");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };
}

function OrderItem({ card }: { card: ProductionOrderCard }) {
  const t = useExtracted("manufacturing");
  const format = useFormatter();

  const quantity =
    card.status === "done"
      ? t("{produced} of {planned} made", {
          produced: format.number(card.producedQuantity),
          planned: format.number(card.quantity),
        })
      : t("{planned} to make", { planned: format.number(card.quantity) });

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-1">
        <span className="font-mono text-xs text-muted-foreground">
          {card.number}
        </span>
        <span className="text-sm font-medium">
          {card.product ?? t("Unknown product")}
        </span>
        <span className="text-xs text-muted-foreground tabular-nums">
          {card.dueOn === null
            ? quantity
            : t("{quantity}, due {date}", {
                quantity,
                date: format.dateTime(new Date(card.dueOn), {
                  dateStyle: "medium",
                  timeZone: "UTC",
                }),
              })}
        </span>
      </CardContent>
    </Card>
  );
}

// #region recipe:production-order-board
/**
 * The organization's production orders in a column for their status. Dragging a
 * draft to Released releases it, and dragging a released or started order to
 * Done completes it with its planned quantity; any other move, or a refused one
 * such as a component shortage, puts the card back. The parent keys it by the
 * cards' statuses, so a refresh starts it from the saved board.
 */
export function ProductionOrderBoard({
  cards,
  canRelease,
  canComplete,
}: {
  cards: readonly ProductionOrderCard[];
  canRelease: boolean;
  canComplete: boolean;
}) {
  const errorMessage = useErrorMessage();
  const label = useStatusLabel();
  const [columns, setColumns] = useState(() => columnsOf(cards));
  const release = useAction(releaseProductionOrder);
  const complete = useAction(completeProductionOrder);
  const pending = release.pending || complete.pending;
  const byId = new Map(cards.map((card) => [card.id, card]));

  const movable = (card: ProductionOrderCard): boolean =>
    card.status === "draft"
      ? canRelease
      : card.status !== "done" && canComplete;

  return (
    <div data-recipe="production-order-board">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(card) => card.id}
        onValueCommit={(_value, meta) => {
          if (meta.kind !== "item") {
            return;
          }

          const from = v.parse(StatusSchema, meta.activeContainer);
          const to = v.parse(StatusSchema, meta.overContainer);
          const card = byId.get(String(meta.event.active.id));

          const run =
            card === undefined
              ? undefined
              : from === "draft" && to === "released"
                ? release.run({ orderId: card.id })
                : from !== "draft" && from !== "done" && to === "done"
                  ? complete.run({ orderId: card.id, produced: card.quantity })
                  : undefined;

          if (run === undefined) {
            setColumns(meta.previousValue);

            return;
          }

          void run.then((result) => {
            if (!result.ok) {
              setColumns(meta.previousValue);
              toast.error(errorMessage(result.error));
            }

            return result;
          });
        }}
      >
        <KanbanBoard className="flex overflow-x-auto">
          {BOARD_STATUSES.map((status) => {
            const column = columns[status] ?? [];

            return (
              <KanbanColumn
                key={status}
                value={status}
                className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-medium">{label(status)}</span>
                  <Badge variant="outline">{column.length}</Badge>
                </div>
                <KanbanColumnContent value={status} className="min-h-16">
                  {column.map((card) => (
                    <KanbanItem
                      key={card.id}
                      value={card.id}
                      disabled={!movable(card) || pending}
                    >
                      <KanbanItemHandle cursor={movable(card)}>
                        <OrderItem card={card} />
                      </KanbanItemHandle>
                    </KanbanItem>
                  ))}
                </KanbanColumnContent>
              </KanbanColumn>
            );
          })}
        </KanbanBoard>
        <KanbanOverlay>
          {({ value, variant }) => {
            const card =
              variant === "item" ? byId.get(String(value)) : undefined;

            return card ? <OrderItem card={card} /> : null;
          }}
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
// #endregion recipe:production-order-board
