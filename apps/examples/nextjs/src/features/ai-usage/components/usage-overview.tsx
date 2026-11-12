import { getExtracted, getFormatter } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getAiUsage, USAGE_WINDOW } from "../ai-usage-queries";
import { ClearCacheButton } from "./clear-cache-button";
import { ModelSpendTable } from "./model-spend-table";
import { SpendChartLazy } from "./spend-chart-lazy";

/** Render inside `<Suspense>`: KPIs, spend per day and the ledger per model. */
export async function UsageOverview() {
  const [usage, permissions, t, format] = await Promise.all([
    getAiUsage(),
    getPermissions(),
    getExtracted("aiUsage"),
    getFormatter(),
  ]);

  const cachedShare =
    usage.inputTokens === 0 ? 0 : usage.cachedInputTokens / usage.inputTokens;

  const kpis = [
    {
      label: t("Runs"),
      value: format.number(usage.runs) + (usage.capped ? "+" : ""),
    },
    {
      label: t("Spend"),
      value: format.number(usage.costMicroUsd / 1_000_000, {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 4,
      }),
    },
    {
      label: t("Tokens in / out"),
      value: `${format.number(usage.inputTokens, { notation: "compact" })} / ${format.number(usage.outputTokens, { notation: "compact" })}`,
    },
    {
      label: t("Cached input"),
      value: format.number(cachedShare, { style: "percent" }),
    },
    { label: t("Failed runs"), value: format.number(usage.failed) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <ul className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        {kpis.map((kpi) => (
          <li key={kpi.label}>
            <Card size="sm">
              <CardContent className="flex flex-col gap-1">
                <span className="text-sm text-muted-foreground">
                  {kpi.label}
                </span>
                <span className="text-xl font-semibold tabular-nums">
                  {kpi.value}
                </span>
              </CardContent>
            </Card>
          </li>
        ))}
      </ul>
      <Card>
        <CardHeader>
          <CardTitle>{t("Spend per day")}</CardTitle>
          <CardDescription>
            {usage.capped
              ? t("The newest {count, number} runs.", { count: USAGE_WINDOW })
              : t("Every run so far.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SpendChartLazy days={usage.days} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Per model")}</CardTitle>
          <CardDescription>
            {t(
              "Cached input is the share of input tokens a provider served from its prompt cache. The call cache below keeps whole answers.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <ModelSpendTable models={usage.models} />
          {can(permissions, "ai_chat.manage") ? (
            <div>
              <ClearCacheButton />
            </div>
          ) : null}
        </CardContent>
      </Card>
    </div>
  );
}

export function UsageOverviewSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        {["runs", "spend", "tokens", "cached", "failed"].map((key) => (
          <Skeleton key={key} className="h-16 w-full" />
        ))}
      </div>
      <Skeleton className="h-64 w-full" />
      <Skeleton className="h-48 w-full" />
    </div>
  );
}
