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
import { Link } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CaseBoardData, CaseCard } from "../cases-queries";

import { moveCase } from "../cases-actions";
import { OPEN_STAGES } from "../cases-stages";
import {
  severityVariant,
  useSeverityLabel,
  useStageLabel,
} from "./case-labels";

type Columns = Record<string, CaseCard[]>;

const StageSchema = v.picklist(OPEN_STAGES);

function columnsOf(cards: readonly CaseCard[]): Columns {
  const columns: Columns = Object.fromEntries(
    OPEN_STAGES.map((stage) => [stage, []]),
  );

  for (const card of cards) {
    columns[card.stage]?.push(card);
  }

  return columns;
}

function CaseItem({ card }: { card: CaseCard }) {
  const t = useExtracted("cases");
  const format = useFormatter();
  const severity = useSeverityLabel();

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-2">
          <span className="font-mono text-xs text-muted-foreground">
            {card.number}
          </span>
          {card.severity === null ? null : (
            <Badge variant={severityVariant(card.severity)}>
              {severity(card.severity)}
            </Badge>
          )}
        </div>
        <Link
          href={`/cases?case=${card.id}`}
          className="text-sm font-medium underline-offset-4 transition-colors hover:underline"
        >
          {card.title}
        </Link>
        <span className="text-xs text-muted-foreground">
          {card.dueOn === null
            ? card.kind
            : t("{kind}, due {date}", {
                kind: card.kind,
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

// #region recipe:case-board
/**
 * The organization's open cases in a column for their stage. Dragging a card to
 * another column moves the case there; a failed move puts it back. The parent
 * keys it by the cards' stages, so a refresh starts it from the saved board.
 */
export function CaseBoard({
  data,
  canMove,
}: {
  data: CaseBoardData;
  canMove: boolean;
}) {
  const errorMessage = useErrorMessage();
  const label = useStageLabel();
  const [columns, setColumns] = useState(() => columnsOf(data.cards));
  const move = useAction(moveCase);
  const byId = new Map(data.cards.map((card) => [card.id, card]));

  return (
    <div data-recipe="case-board">
      <Kanban
        value={columns}
        onValueChange={setColumns}
        getItemValue={(card) => card.id}
        onValueCommit={(_value, meta) => {
          if (meta.kind !== "item") {
            return;
          }

          const from = v.parse(StageSchema, meta.activeContainer);
          const to = v.parse(StageSchema, meta.overContainer);
          const card = byId.get(String(meta.event.active.id));

          const stageId =
            card === undefined ? undefined : data.stages[card.pipelineId]?.[to];

          if (from === to || card === undefined || stageId === undefined) {
            setColumns(meta.previousValue);

            return;
          }

          void move.run({ caseId: card.id, stageId }).then((result) => {
            if (!result.ok) {
              setColumns(meta.previousValue);
              toast.error(errorMessage(result.error));
            }

            return result;
          });
        }}
      >
        <KanbanBoard className="flex overflow-x-auto">
          {OPEN_STAGES.map((stage) => {
            const column = columns[stage] ?? [];

            return (
              <KanbanColumn
                key={stage}
                value={stage}
                className="w-72 shrink-0 gap-3 rounded-lg bg-muted/50 p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-medium">{label(stage)}</span>
                  <Badge variant="outline">{column.length}</Badge>
                </div>
                <KanbanColumnContent value={stage} className="min-h-16">
                  {column.map((card) => (
                    <KanbanItem
                      key={card.id}
                      value={card.id}
                      disabled={!canMove || move.pending}
                    >
                      <KanbanItemHandle cursor={canMove}>
                        <CaseItem card={card} />
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

            return card ? <CaseItem card={card} /> : null;
          }}
        </KanbanOverlay>
      </Kanban>
    </div>
  );
}
// #endregion recipe:case-board
