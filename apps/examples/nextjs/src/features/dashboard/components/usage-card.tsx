import { getExtracted, getFormatter } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { activeOrganizationId } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getUsage } from "../dashboard-queries";

/** Render inside `<Suspense>`: this period's usage per meter. */
export async function UsageCard() {
  const organizationId = activeOrganizationId(await getSession());
  if (!organizationId) return null;
  const [meters, t, format] = await Promise.all([
    getUsage(organizationId),
    getExtracted("dashboard"),
    getFormatter(),
  ]);
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
              <span className="text-muted-foreground tabular-nums">
                {meter.unlimited || meter.limit === null
                  ? t("{used} used, no limit", {
                      used: format.number(meter.used),
                    })
                  : t("{used} of {limit}", {
                      used: format.number(meter.used),
                      limit: format.number(meter.limit),
                    })}
              </span>
            </div>
            <Progress
              value={
                meter.unlimited || !meter.limit
                  ? 0
                  : Math.min(100, (meter.used / meter.limit) * 100)
              }
            />
            <p className="text-muted-foreground text-xs">
              {t("Resets {date}", {
                date: format.dateTime(new Date(meter.resetsAt), {
                  dateStyle: "medium",
                }),
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
