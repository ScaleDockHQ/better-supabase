"use client";

import type { Money } from "better-supabase/commerce";

import { formatMoney } from "better-supabase/commerce";
import { useAction } from "better-supabase/react";
import { useExtracted, useLocale } from "next-intl";
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

import type { BoardDeal, BoardStage } from "../crm-queries";

import { moveDeal } from "../crm-actions";

type Columns = Record<string, BoardDeal[]>;

function columnsOf(
  stages: readonly BoardStage[],
  deals: readonly BoardDeal[],
): Columns {
  const columns: Columns = Object.fromEntries(
    stages.map((stage) => [stage.id, []]),
  );

  for (const deal of deals) {
    columns[deal.stageId]?.push(deal);
  }

  return columns;
}

function DealCard({ deal }: { deal: BoardDeal }) {
  const t = useExtracted("crm");

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-2">
        <div className="flex flex-col gap-0.5">
          <span className="text-sm font-medium">{deal.name}</span>
          <span className="text-xs text-muted-foreground tabular-nums">
            {deal.identifier}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-1">
          <Badge variant="outline">
            {t("{days, plural, one {# day} other {# days}} in stage", {
              days: deal.daysInStage,
            })}
          </Badge>
          {deal.rotting ? (
            <Badge variant="warning-light">{t("Stalled")}</Badge>
          ) : null}
          {deal.overdue ? (
            <Badge variant="destructive-light">{t("Overdue")}</Badge>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}

/**
 * The board's columns. Dragging a deal to another column moves its stage;
 * a refused move puts it back. The parent keys it by the deals' positions,
 * so a server refresh starts it from the saved board.
 */
export function DealKanban({
  stages,
  deals,
  canMove,
}: {
  stages: readonly BoardStage[];
  deals: readonly BoardDeal[];
  canMove: boolean;
}) {
  const t = useExtracted("crm");
  const locale = useLocale();
  const errorMessage = useErrorMessage();
  const [columns, setColumns] = useState(() => columnsOf(stages, deals));
  const move = useAction(moveDeal);
  const byId = new Map(deals.map((deal) => [deal.id, deal]));

  const total = (totals: readonly Money[]) =>
    totals.map((amount) => formatMoney(amount, locale)).join(" + ");

  return (
    <Kanban
      value={columns}
      onValueChange={setColumns}
      getItemValue={(deal) => deal.id}
      onValueCommit={(_value, meta) => {
        if (
          meta.kind !== "item" ||
          meta.activeContainer === meta.overContainer
        ) {
          return;
        }

        void move
          .run({
            dealId: String(meta.event.active.id),
            stageId: meta.overContainer,
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
        {stages.map((stage) => (
          <KanbanColumn
            key={stage.id}
            value={stage.id}
            className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate text-sm font-medium">
                  {stage.name}
                </span>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {stage.totals.length === 0 ? "" : total(stage.totals)}
                </span>
              </div>
              <Badge
                variant={
                  stage.category === "won"
                    ? "success-light"
                    : stage.category === "lost"
                      ? "destructive-light"
                      : "secondary"
                }
              >
                {stage.count}
              </Badge>
            </div>
            <KanbanColumnContent value={stage.id} className="min-h-16">
              {(columns[stage.id] ?? []).map((deal) => (
                <KanbanItem key={deal.id} value={deal.id} disabled={!canMove}>
                  <KanbanItemHandle cursor={canMove}>
                    <DealCard deal={deal} />
                  </KanbanItemHandle>
                </KanbanItem>
              ))}
              {stage.category === "open" ? null : (
                <p className="text-xs text-muted-foreground">
                  {t("Drop a deal here to close it.")}
                </p>
              )}
            </KanbanColumnContent>
          </KanbanColumn>
        ))}
      </KanbanBoard>
      <KanbanOverlay>
        {({ value, variant }) => {
          const deal = variant === "item" ? byId.get(String(value)) : undefined;

          return deal ? <DealCard deal={deal} /> : null;
        }}
      </KanbanOverlay>
    </Kanban>
  );
}
