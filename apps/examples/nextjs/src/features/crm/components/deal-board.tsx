import { KanbanIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { loadDealBoard, settle } from "../crm-queries";
import { CreateDealDialog } from "./create-deal-dialog";
import { CreatePipelineButton } from "./create-pipeline-button";
import { CrmLoadError } from "./crm-load-error";
import { DealKanban } from "./deal-kanban";

// #region recipe:deal-board
/**
 * Render inside `<Suspense>`: one column per stage of the default deal
 * pipeline. Dragging a deal saves its new stage through `moveDeal`.
 */
export async function DealBoard() {
  const [session, t] = await Promise.all([getSession(), getExtracted("crm")]);

  if (!can(session, "deals.read")) {
    forbidden();
  }

  const board = await settle(loadDealBoard);

  if (board.kind === "no-organization") {
    return null;
  }

  const pipeline = board.kind === "ok" ? board.data.pipeline : null;

  const openStages =
    board.kind === "ok"
      ? board.data.stages
          .filter((stage) => stage.category === "open")
          .map((stage) => ({ value: stage.id, label: stage.name }))
      : [];

  return (
    <Card data-recipe="deal-board">
      <CardHeader>
        <CardTitle>{pipeline?.name ?? t("Deals")}</CardTitle>
        <CardDescription>
          {t("Drag a deal to another stage to move it.")}
        </CardDescription>
        {pipeline && can(session, "deals.write") ? (
          <CardAction>
            <CreateDealDialog pipelineId={pipeline.id} stages={openStages} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {board.kind === "error" ? (
          <CrmLoadError title={t("The board didn't load")} />
        ) : board.data.pipeline === null ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <KanbanIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No pipeline yet")}</EmptyTitle>
              <EmptyDescription>
                {can(session, "pipelines.manage")
                  ? t(
                      "Start with six stages, from qualified to closed won or lost.",
                    )
                  : t("Ask an admin to create the sales pipeline.")}
              </EmptyDescription>
            </EmptyHeader>
            {can(session, "pipelines.manage") ? (
              <EmptyContent>
                <CreatePipelineButton />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <DealKanban
            key={board.data.deals
              .map((deal) => `${deal.id}:${deal.stageId}`)
              .join(",")}
            stages={board.data.stages}
            deals={board.data.deals}
            canMove={can(session, "deals.write")}
          />
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:deal-board

export function DealBoardSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
