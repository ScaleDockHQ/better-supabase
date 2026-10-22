import { SquareKanbanIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button, buttonVariants } from "@/components/ui/button";
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
import { Link } from "@/i18n/navigation";

import { getOrderBoard } from "../kitchen-queries";
import { KitchenLive } from "./kitchen-live";
import { OrderStateBoard } from "./order-state-board";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: loads the board and keeps it live. */
export async function OrderBoard() {
  const session = await getSession();

  if (!can(session, "orders.read") && !can(session, "orders.prepare")) {
    forbidden();
  }

  const canPrepare =
    can(session, "orders.prepare") || can(session, "orders.manage");

  const [board, t] = await Promise.all([getOrderBoard(), getExtracted("shop")]);

  if (board.kind === "no-organization") {
    return null;
  }

  if (board.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The board didn't load")}</AlertTitle>
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

  const { organizationId, cards } = board.data;

  if (cards.length === 0) {
    return (
      <>
        <KitchenLive organizationId={organizationId} />
        <Empty className="border" data-recipe="order-state-board">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <SquareKanbanIcon />
            </EmptyMedia>
            <EmptyTitle>{t("Nothing in the kitchen today")}</EmptyTitle>
            <EmptyDescription>
              {t("Orders show up here once they're sent to the kitchen.")}
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Link
              href="/shop/orders"
              className={buttonVariants({ size: "sm" })}
            >
              {t("Open orders")}
            </Link>
          </EmptyContent>
        </Empty>
      </>
    );
  }

  return (
    <>
      <KitchenLive organizationId={organizationId} />
      <OrderStateBoard
        key={cards.map((card) => `${card.orderId}:${card.state}`).join(",")}
        cards={cards}
        canPrepare={canPrepare}
      />
    </>
  );
}

export function OrderBoardSkeleton() {
  return (
    <div className="flex gap-4 overflow-x-auto">
      {["queued", "preparing", "ready", "served"].map((key) => (
        <div key={key} className="flex w-72 shrink-0 flex-col gap-3">
          <Skeleton className="h-6 w-24" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
        </div>
      ))}
    </div>
  );
}
