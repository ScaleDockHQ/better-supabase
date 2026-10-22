"use client";

import { PREPARATION_STATES } from "better-supabase/blocks/orders";
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

import type { BoardCardView } from "../kitchen-queries";

import { bumpTicket } from "../kitchen-actions";
import { preparationBadgeVariant, usePreparationLabel } from "./kitchen-labels";

type Columns = Record<string, BoardCardView[]>;

const StateSchema = v.picklist(PREPARATION_STATES);

function columnsOf(cards: readonly BoardCardView[]): Columns {
  const columns: Columns = Object.fromEntries(
    PREPARATION_STATES.map((state) => [state, []]),
  );

  for (const card of cards) {
    columns[card.state]?.push(card);
  }

  return columns;
}

function OrderCard({ card }: { card: BoardCardView }) {
  const t = useExtracted("shop");
  const format = useFormatter();

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-1">
        <span className="text-sm font-medium tabular-nums">
          {t("Order {number}", { number: card.number })}
        </span>
        <span className="text-xs text-muted-foreground tabular-nums">
          {t("{ready, number} of {lines, number} ready, sent at {time}", {
            ready: card.ready,
            lines: card.lines,
            time: format.dateTime(new Date(card.sentAt), {
              timeStyle: "short",
            }),
          })}
        </span>
      </CardContent>
    </Card>
  );
}

// #region recipe:order-state-board
/**
 * The orders sent to the kitchen today, in a column for the state of their
 * least advanced line. Dragging a card to a later column moves every line of
 * the order up to that state; a move back or within a column puts the card
 * back. The parent keys it by the cards' states, so a refresh starts it from
 * the saved board.
 */
export function OrderStateBoard({
  cards,
  canPrepare,
}: {
  cards: readonly BoardCardView[];
  canPrepare: boolean;
}) {
  const t = useExtracted("shop");
  const errorMessage = useErrorMessage();
  const label = usePreparationLabel();
  const [columns, setColumns] = useState(() => columnsOf(cards));
  const bump = useAction(bumpTicket);
  const byId = new Map(cards.map((card) => [card.orderId, card]));

  return (
    <div data-recipe="order-state-board">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(card) => card.orderId}
        onValueCommit={(_value, meta) => {
          if (meta.kind !== "item") {
            return;
          }

          const from = v.parse(StateSchema, meta.activeContainer);
          const to = v.parse(StateSchema, meta.overContainer);

          if (
            PREPARATION_STATES.indexOf(to) <= PREPARATION_STATES.indexOf(from)
          ) {
            setColumns(meta.previousValue);

            if (from !== to) {
              toast.warning(t("An order only moves forward on this board."));
            }

            return;
          }

          void bump
            .run({
              orderId: String(meta.event.active.id),
              state: to,
              stationId: null,
            })
            .then((result) => {
              if (!result.ok) {
                setColumns(meta.previousValue);
                toast.error(errorMessage(result.error));
              }
            });
        }}
      >
        <KanbanBoard className="flex overflow-x-auto">
          {PREPARATION_STATES.map((state) => {
            const column = columns[state] ?? [];
            const count = column.length;

            return (
              <KanbanColumn
                key={state}
                value={state}
                className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <Badge variant={preparationBadgeVariant(state)}>
                    {label(state)}
                  </Badge>
                  <Badge variant="outline">{count}</Badge>
                </div>
                <KanbanColumnContent value={state} className="min-h-16">
                  {column.map((card) => (
                    <KanbanItem
                      key={card.orderId}
                      value={card.orderId}
                      disabled={!canPrepare || bump.pending}
                    >
                      <KanbanItemHandle cursor={canPrepare}>
                        <OrderCard card={card} />
                      </KanbanItemHandle>
                    </KanbanItem>
                  ))}
                  {count === 0 ? (
                    <p className="text-xs text-muted-foreground">
                      {t("No orders here.")}
                    </p>
                  ) : null}
                </KanbanColumnContent>
              </KanbanColumn>
            );
          })}
        </KanbanBoard>
        <KanbanOverlay>
          {({ value, variant }) => {
            const card =
              variant === "item" ? byId.get(String(value)) : undefined;

            return card ? <OrderCard card={card} /> : null;
          }}
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
// #endregion recipe:order-state-board
