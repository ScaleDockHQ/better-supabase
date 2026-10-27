import { KanbanIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";
import * as v from "valibot";

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
import { getFields } from "@/features/custom-fields/custom-fields-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getTeams, getWorkBoard, settle } from "../work-queries";
import { WORK_ITEM_SUBJECT } from "../work-types";
import { CreateWorkItemDialog } from "./create-work-item-dialog";
import { TeamPicker } from "./team-picker";
import { WorkItemBoard } from "./work-item-board";
import { WorkLoadError } from "./work-load-error";

const TeamParam = v.pipe(v.string(), v.uuid());

/**
 * Render inside `<Suspense>`: the team picker and the board of the default work
 * item workflow, scoped to `teamId` when one is picked.
 */
export async function WorkBoard({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, params, permissions] = await Promise.all([
    getExtracted("work"),
    searchParams,
    getPermissions(),
  ]);

  if (!can(permissions, "work_items.read")) {
    forbidden();
  }

  const parsed = v.safeParse(TeamParam, params["team"]);
  const team = parsed.success ? parsed.output : null;

  const [board, teams, fields] = await Promise.all([
    settle(() => getWorkBoard(team)),
    settle(getTeams),
    getFields(WORK_ITEM_SUBJECT),
  ]);

  if (board.kind === "no-organization") {
    return null;
  }

  const teamOptions = teams.kind === "ok" ? teams.data : [];
  const customFields = fields.kind === "ok" ? fields.data : [];
  const teamId = teamOptions.find((each) => each.id === team)?.id ?? null;
  const canWrite = can(permissions, "work_items.write");

  const empty =
    board.kind === "ok" &&
    (board.data.stages.length === 0 || board.data.items.length === 0);

  return (
    <div className="flex flex-col gap-6">
      {teams.kind === "error" ? (
        <WorkLoadError title={t("The teams didn't load")} />
      ) : (
        <TeamPicker
          teams={teamOptions}
          teamId={teamId}
          canManage={can(permissions, "teams.manage")}
        />
      )}
      <Card>
        <CardHeader>
          <CardTitle>{t("Board")}</CardTitle>
          <CardDescription>
            {t(
              "Drag an item to another column to change its state, or within a column to reorder it.",
            )}
          </CardDescription>
          {canWrite && !empty ? (
            <CardAction>
              <CreateWorkItemDialog
                teams={teamOptions}
                defaultTeamId={teamId}
                customFields={customFields}
              />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>
          {board.kind === "error" ? (
            <WorkLoadError title={t("The board didn't load")} />
          ) : empty ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <KanbanIcon />
                </EmptyMedia>
                <EmptyTitle>
                  {teamId === null
                    ? t("No work items yet")
                    : t("This team has no work items")}
                </EmptyTitle>
                <EmptyDescription>
                  {canWrite
                    ? t(
                        "Create the first item. Its workflow is set up with it, from triage to done.",
                      )
                    : t("Ask a member with write access to create one.")}
                </EmptyDescription>
              </EmptyHeader>
              {canWrite ? (
                <EmptyContent>
                  <CreateWorkItemDialog
                    teams={teamOptions}
                    defaultTeamId={teamId}
                    customFields={customFields}
                  />
                </EmptyContent>
              ) : null}
            </Empty>
          ) : (
            <WorkItemBoard
              key={board.data.items
                .map((item) => `${item.id}:${item.stageId}:${item.rank}`)
                .join(",")}
              stages={board.data.stages}
              items={board.data.items}
              canMove={canWrite}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function WorkBoardSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-96 rounded-xl" />
    </div>
  );
}
