import { BriefcaseIcon, UserPlusIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadHiringBoard, settle } from "../people-queries";
import { AddCandidateDialog } from "./add-candidate-dialog";
import { CreateOpeningDialog } from "./create-opening-dialog";
import { HiringKanban } from "./hiring-kanban";
import { PeopleLoadError } from "./people-load-error";

// #region recipe:hiring-board
/**
 * Render inside `<Suspense>`: the candidates of one opening as cards in its
 * stage columns. Dragging a card to Hired or Rejected closes the application;
 * to another open stage, moves it. `?job=` picks the opening.
 */
export async function HiringBoard({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, query, permissions] = await Promise.all([
    getExtracted("people"),
    searchParams,
    getPermissions(),
  ]);

  if (!can(permissions, "hiring.read")) {
    forbidden();
  }

  const board = await settle(loadHiringBoard);

  if (board.kind === "no-organization") {
    return null;
  }

  const canManage = can(permissions, "hiring.manage");
  const canWrite = can(permissions, "hiring.write");
  const jobs = board.kind === "ok" ? board.data.jobs : [];
  const job = jobs.find((item) => item.id === query["job"]) ?? jobs[0];

  const cards =
    board.kind === "ok" && job
      ? board.data.cards.filter((card) => card.jobId === job.id)
      : [];

  const createOpening = canManage ? <CreateOpeningDialog /> : null;

  return (
    <Card data-recipe="hiring-board">
      <CardHeader>
        <CardTitle>{job?.title ?? t("Hiring")}</CardTitle>
        <CardDescription>
          {t("Drag a candidate to the next stage, or to Hired or Rejected.")}
        </CardDescription>
        {jobs.length > 0 || board.kind === "error" ? (
          <CardAction className="flex items-center gap-2">
            {job && canWrite && board.kind === "ok" && cards.length > 0 ? (
              <AddCandidateDialog
                jobId={job.id}
                candidates={board.data.candidates}
              />
            ) : null}
            {createOpening}
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {board.kind === "error" ? (
          <PeopleLoadError title={t("The hiring board didn't load")} />
        ) : job === undefined ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BriefcaseIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No openings yet")}</EmptyTitle>
              <EmptyDescription>
                {canManage
                  ? t("Create an opening, then add candidates to it.")
                  : t("Ask a hiring manager to create an opening.")}
              </EmptyDescription>
            </EmptyHeader>
            {createOpening ? (
              <EmptyContent>{createOpening}</EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <>
            {jobs.length > 1 ? (
              <nav
                aria-label={t("Openings")}
                className="flex flex-wrap items-center gap-2"
              >
                {jobs.map((item) => (
                  <Link
                    key={item.id}
                    href={`/people/hiring?job=${item.id}`}
                    aria-current={item.id === job.id ? "page" : undefined}
                    className={buttonVariants({
                      variant: item.id === job.id ? "secondary" : "ghost",
                      size: "sm",
                    })}
                  >
                    {item.title}
                    {item.status === "open" ? null : (
                      <Badge variant="outline">
                        {item.status === "draft" ? t("Draft") : t("Closed")}
                      </Badge>
                    )}
                  </Link>
                ))}
              </nav>
            ) : null}
            {cards.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <UserPlusIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No candidates yet")}</EmptyTitle>
                  <EmptyDescription>
                    {t("Candidates start in the first stage of the pipeline.")}
                  </EmptyDescription>
                </EmptyHeader>
                {canWrite ? (
                  <EmptyContent>
                    <AddCandidateDialog
                      jobId={job.id}
                      candidates={board.data.candidates}
                    />
                  </EmptyContent>
                ) : null}
              </Empty>
            ) : (
              <HiringKanban
                key={cards
                  .map((card) => `${card.id}:${card.stageId}`)
                  .join(",")}
                stages={board.data.stages}
                cards={cards}
                canMove={canWrite}
              />
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:hiring-board

export function HiringBoardSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
