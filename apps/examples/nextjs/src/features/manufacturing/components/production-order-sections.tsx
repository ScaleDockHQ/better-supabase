import { FactoryIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

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
import { settle } from "@/features/shop/shop-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getProductionOrderBoard } from "../manufacturing-queries";
import { ProductionOrderBoard } from "./production-order-board";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the production orders by status. */
export async function ProductionOrderBoardSection() {
  const [t, permissions] = await Promise.all([
    getExtracted("manufacturing"),
    getPermissions(),
  ]);

  const board = await settle(getProductionOrderBoard);

  if (board.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Production orders")}</FrameTitle>
        <FrameDescription>
          {t(
            "Each order in its status. Drag a draft to Released to allocate its components, and a running order to Done to receive its output.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {board.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The production orders didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : board.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FactoryIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No production orders")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Give a product a bill of materials, then create an order for it through the API or from material requirements.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/manufacturing"
              >
                {t("Read the manufacturing guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <ProductionOrderBoard
            key={board.data
              .map((card) => `${card.id}:${card.status}`)
              .join(",")}
            cards={board.data}
            canRelease={can(permissions, "manufacturing.write")}
            canComplete={can(permissions, "manufacturing.produce")}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

export function ProductionOrderBoardSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-96" />
      </FrameHeader>
      <FramePanel className="flex gap-3">
        {[0, 1, 2, 3].map((column) => (
          <Skeleton key={column} className="h-48 w-72 shrink-0" />
        ))}
      </FramePanel>
    </Frame>
  );
}
