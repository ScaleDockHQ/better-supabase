// #region recipe:usage-meter
"use client";

import { useUsageMeter } from "better-supabase/blocks/usage/react";
import { tenantOf } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/lib/hooks";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/** The API schema `gen` wrote for the usage block. */
const API_SCHEMA = blockConfig.usage.api;

/** This period's usage per meter against the plan's quota. */
export function UsageCard() {
  const t = useExtracted("dashboard");
  const format = useFormatter();
  const organizationId = tenantOf(useAuth()) ?? null;
  const { meters } = useUsageMeter({
    organizationId,
    meters: ["api.calls", "customers.created"],
    schema: API_SCHEMA,
  });
  if (!organizationId) return null;
  if (meters === undefined) return <UsageCardSkeleton />;
  const labels = new Map([
    ["api.calls", t("API calls")],
    ["customers.created", t("Customers added")],
  ]);
  return (
    <Card data-testid="usage">
      <CardHeader>
        <CardTitle>{t("Usage this period")}</CardTitle>
        <CardDescription>
          {t("Counted by the usage module, limited by your plan.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        {meters.map((meter) => (
          <div key={meter.meter} className="space-y-2">
            <div className="flex items-baseline justify-between gap-2 text-sm">
              <span className="font-medium">
                {labels.get(meter.meter) ?? meter.meter}
              </span>
              <span
                className={
                  meter.exceeded
                    ? "text-destructive tabular-nums"
                    : "text-muted-foreground tabular-nums"
                }
              >
                {meter.limit === undefined
                  ? t("{used} used, no limit", {
                      used: format.number(meter.used),
                    })
                  : t("{used} of {limit}", {
                      used: format.number(meter.used),
                      limit: format.number(meter.limit),
                    })}
              </span>
            </div>
            <Progress value={(meter.fraction ?? 0) * 100} />
            <p className="text-muted-foreground text-xs">
              {t("Resets {date}", {
                date: format.dateTime(
                  new Date(meter.resetsAt.epochMilliseconds),
                  { dateStyle: "medium" },
                ),
              })}
            </p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function UsageCardSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:usage-meter
