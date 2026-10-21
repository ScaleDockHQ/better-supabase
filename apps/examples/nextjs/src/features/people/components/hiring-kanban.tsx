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

import type { HiringCard, HiringStage } from "../people-queries";

import { closeApplication, moveApplication } from "../people-actions";

type Columns = Record<string, HiringCard[]>;

function columnsOf(
  stages: readonly HiringStage[],
  cards: readonly HiringCard[],
): Columns {
  const columns: Columns = Object.fromEntries(
    stages.map((stage) => [stage.id, []]),
  );

  for (const card of cards) {
    columns[card.stageId]?.push(card);
  }

  return columns;
}

function CandidateCard({ card }: { card: HiringCard }) {
  return (
    <Card size="sm">
      <CardContent>
        <span className="text-sm font-medium">{card.name}</span>
      </CardContent>
    </Card>
  );
}

function stageBadge(category: string) {
  if (category === "hired") {
    return "success-light";
  }

  return category === "rejected" || category === "withdrawn"
    ? "destructive-light"
    : "secondary";
}

/**
 * The stage columns of one opening. A refused move puts the card back. The
 * parent keys it by the cards' stages, so a refresh starts from the saved
 * board.
 */
export function HiringKanban({
  stages,
  cards,
  canMove,
}: {
  stages: readonly HiringStage[];
  cards: readonly HiringCard[];
  canMove: boolean;
}) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();
  const [columns, setColumns] = useState(() => columnsOf(stages, cards));
  const move = useAction(moveApplication);
  const close = useAction(closeApplication);
  const byId = new Map(cards.map((card) => [card.id, card]));
  const categoryOf = new Map(stages.map((stage) => [stage.id, stage.category]));

  return (
    <Kanban
      value={columns}
      onValueChange={setColumns}
      getItemValue={(card) => card.id}
      onValueCommit={(_value, meta) => {
        if (
          meta.kind !== "item" ||
          meta.activeContainer === meta.overContainer
        ) {
          return;
        }

        const applicationId = String(meta.event.active.id);
        const category = categoryOf.get(meta.overContainer);

        const saved =
          category === "hired" || category === "rejected"
            ? close.run({ applicationId, outcome: category })
            : category === "active"
              ? move.run({ applicationId, stageId: meta.overContainer })
              : undefined;

        if (saved === undefined) {
          setColumns(meta.previousValue);
          toast.error(t("A candidate can't be moved to that stage here."));

          return;
        }

        void saved.then((result) => {
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
            className="w-64 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
          >
            <div className="flex items-center justify-between gap-2">
              <span className="truncate text-sm font-medium">{stage.name}</span>
              <Badge variant={stageBadge(stage.category)}>
                {columns[stage.id]?.length ?? 0}
              </Badge>
            </div>
            <KanbanColumnContent value={stage.id} className="min-h-16">
              {(columns[stage.id] ?? []).map((card) => (
                <KanbanItem key={card.id} value={card.id} disabled={!canMove}>
                  <KanbanItemHandle cursor={canMove}>
                    <CandidateCard card={card} />
                  </KanbanItemHandle>
                </KanbanItem>
              ))}
            </KanbanColumnContent>
          </KanbanColumn>
        ))}
      </KanbanBoard>
      <KanbanOverlay>
        {({ value, variant }) => {
          const card = variant === "item" ? byId.get(String(value)) : undefined;

          return card ? <CandidateCard card={card} /> : null;
        }}
      </KanbanOverlay>
    </Kanban>
  );
}
