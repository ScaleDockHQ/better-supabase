import type { FundingPeriod } from "better-supabase/blocks/funding";

import { HandCoinsIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { connection } from "next/server";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
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

import { getAwards } from "../funding-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the organization's awards, each with its product,
 * the units it grants per period and the units used in its latest period.
 * Members with `funding.read` see it.
 */
export async function AwardUsage() {
  await connection();

  const [state, t, format] = await Promise.all([
    getAwards(),
    getExtracted("funding"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The awards didn't load")}</AlertTitle>
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

  const awards = state.data;

  if (awards.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <HandCoinsIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No awards yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Add a funding product with its rate, then record the units a funder awards a customer.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/funding"
          >
            {t("Read the funding guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const per = (period: FundingPeriod, count: number) => {
    const units = format.number(count);

    switch (period) {
      case "week": {
        return t("{units} per week", { units });
      }

      case "month": {
        return t("{units} per month", { units });
      }

      case "total": {
        return t("{units} in total", { units });
      }

      default: {
        const unknown: never = period;

        return unknown;
      }
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Awards")}</CardTitle>
        <CardDescription>
          {t("The units each award grants and the units used this period.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {awards.map((award) => (
          <div
            key={award.id}
            className="flex flex-wrap items-center gap-2 border-b pb-4 last:border-b-0 last:pb-0"
          >
            <span className="text-sm font-medium">{award.product}</span>
            <span className="text-sm text-muted-foreground tabular-nums">
              {per(award.period, award.units)}
            </span>
            {award.reference ? (
              <span className="text-xs text-muted-foreground">
                {award.reference}
              </span>
            ) : null}
            <Badge
              variant={award.over > 0 ? "warning-light" : "success-light"}
              className="tabular-nums"
            >
              {award.over > 0
                ? t("{used} used, {over} over", {
                    used: format.number(award.used),
                    over: format.number(award.over),
                  })
                : t("{used} used", { used: format.number(award.used) })}
            </Badge>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function AwardUsageSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
