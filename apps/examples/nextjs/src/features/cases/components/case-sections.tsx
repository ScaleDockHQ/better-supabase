import {
  FileWarningIcon,
  MousePointerClickIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { connection } from "next/server";
import * as v from "valibot";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { settle } from "@/features/people/people-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getCaseBoard, getCaseDetail } from "../cases-queries";
import { CaseBoard } from "./case-board";
import { CaseDetail } from "./case-detail";

const CaseParam = v.pipe(v.string(), v.uuid());

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

async function CasesLoadError({ title }: { title: string }) {
  const t = await getExtracted("cases");

  return (
    <Alert variant="destructive">
      <TriangleAlertIcon />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
      <AlertAction>
        <form action={retry}>
          <Button size="sm" variant="outline" type="submit">
            {t("Retry")}
          </Button>
        </form>
      </AlertAction>
    </Alert>
  );
}

/** Render inside `<Suspense>`: the board of open cases by stage. */
export async function CaseBoardSection() {
  const [t, permissions] = await Promise.all([
    getExtracted("cases"),
    getPermissions(),
  ]);

  const board = await settle(getCaseBoard);

  if (board.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Open cases")}</FrameTitle>
        <FrameDescription>
          {t(
            "Each open case in its stage. Drag a card to move it; closing happens on the case once nothing blocks it.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {board.kind === "error" ? (
          <CasesLoadError title={t("The cases didn't load")} />
        ) : board.data.cards.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileWarningIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No open cases")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Nonconformities, complaints and incidents land here when someone reports one, through the API or a public form.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/cases"
              >
                {t("Read the cases guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <CaseBoard
            key={board.data.cards
              .map((card) => `${card.id}:${card.stage}`)
              .join(",")}
            data={board.data}
            canMove={can(permissions, "cases.write")}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

/**
 * Render inside `<Suspense>`: the case `?case=<id>` picks, with its blockers
 * and actions.
 */
export async function CaseDetailSection({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, query, permissions] = await Promise.all([
    getExtracted("cases"),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  const picked = v.safeParse(CaseParam, query["case"]);

  if (!picked.success) {
    return (
      <Frame spacing="sm">
        <FramePanel>
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <MousePointerClickIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Pick a case")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Open a case on the board to see what still stops it from closing.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </FramePanel>
      </Frame>
    );
  }

  const detail = await settle(() => getCaseDetail(picked.output));

  if (detail.kind === "no-organization") {
    return null;
  }

  return detail.kind === "error" ? (
    <Frame spacing="sm">
      <FramePanel>
        <CasesLoadError title={t("The case didn't load")} />
      </FramePanel>
    </Frame>
  ) : (
    <CaseDetail
      detail={detail.data}
      canClose={can(permissions, "cases.close") || detail.data.isOwner}
    />
  );
}

export function CaseBoardSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel className="flex gap-3">
        {[0, 1, 2, 3].map((column) => (
          <Skeleton key={column} className="h-48 w-72 shrink-0" />
        ))}
      </FramePanel>
    </Frame>
  );
}

export function CaseDetailSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-4 w-32" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-32" />
      </FramePanel>
    </Frame>
  );
}
