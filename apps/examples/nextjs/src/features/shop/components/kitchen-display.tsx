import { ChefHatIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden } from "next/navigation";
import * as v from "valibot";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
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
import { Link } from "@/i18n/navigation";

import { getKitchen } from "../kitchen-queries";
import { KitchenLive } from "./kitchen-live";
import { KitchenTicket } from "./kitchen-ticket";

const StationParam = v.pipe(v.string(), v.uuid());

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

// #region recipe:kitchen-display
/**
 * Render inside `<Suspense>`: the open tickets at one station, or at every
 * station, oldest first. Each ticket moves its lines to the next state, and the
 * page refreshes when a line changes anywhere in the kitchen.
 */
export async function KitchenDisplay({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, params] = await Promise.all([getSession(), searchParams]);

  if (!can(session, "orders.read") && !can(session, "orders.prepare")) {
    forbidden();
  }

  const canPrepare =
    can(session, "orders.prepare") || can(session, "orders.manage");

  const [kitchen, t] = await Promise.all([
    getKitchen(
      v.is(StationParam, params["station"]) ? params["station"] : null,
    ),
    getExtracted("shop"),
  ]);

  if (kitchen.kind === "no-organization") {
    return null;
  }

  if (kitchen.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="kitchen-display">
        <TriangleAlertIcon />
        <AlertTitle>{t("The kitchen didn't load")}</AlertTitle>
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

  const { organizationId, stations, stationId, tickets } = kitchen.data;

  return (
    <div data-recipe="kitchen-display" className="flex flex-col gap-4">
      <KitchenLive organizationId={organizationId} />
      {stations.length > 1 ? (
        <nav aria-label={t("Stations")} className="flex flex-wrap gap-1">
          <Link
            href="/shop/kitchen"
            aria-current={stationId === null ? "page" : undefined}
            className={buttonVariants({
              size: "sm",
              variant: stationId === null ? "secondary" : "ghost",
            })}
          >
            {t("All stations")}
          </Link>
          {stations.map((each) => (
            <Link
              key={each.id}
              href={`/shop/kitchen?station=${each.id}`}
              aria-current={stationId === each.id ? "page" : undefined}
              className={buttonVariants({
                size: "sm",
                variant: stationId === each.id ? "secondary" : "ghost",
              })}
            >
              {each.name}
            </Link>
          ))}
        </nav>
      ) : null}
      {tickets.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <ChefHatIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No open tickets")}</EmptyTitle>
            <EmptyDescription>
              {t(
                "Send a paid order to the kitchen and its lines show up here.",
              )}
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
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {tickets.map((ticket) => (
            <KitchenTicket
              key={ticket.orderId}
              ticket={ticket}
              stationId={stationId}
              canPrepare={canPrepare}
            />
          ))}
        </div>
      )}
    </div>
  );
}
// #endregion recipe:kitchen-display

export function KitchenDisplaySkeleton() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {["a", "b", "c"].map((key) => (
        <Card key={key} size="sm">
          <CardHeader>
            <Skeleton className="h-5 w-24" />
            <Skeleton className="h-4 w-16" />
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-3/4" />
          </CardContent>
          <CardFooter>
            <Skeleton className="h-8 w-full" />
          </CardFooter>
        </Card>
      ))}
    </div>
  );
}
