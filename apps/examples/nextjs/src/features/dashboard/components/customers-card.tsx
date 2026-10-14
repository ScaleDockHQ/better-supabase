import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getSession } from "@/features/user/user-queries";

import { getCustomerCounts } from "../dashboard-queries";

/** Render inside `<Suspense>`: new customers over 30 days, by status. */
export async function CustomersCard() {
  const organizationId = tenantOf(await getSession());
  if (!organizationId) return null;
  const [counts, t, format] = await Promise.all([
    getCustomerCounts(organizationId),
    getExtracted("dashboard"),
    getFormatter(),
  ]);
  const rows = [
    { key: "lead", label: t("Leads"), value: counts.lead },
    { key: "active", label: t("Active"), value: counts.active },
  ];
  return (
    <Card data-testid="customer-metrics">
      <CardHeader>
        <CardTitle>{t("New customers")}</CardTitle>
        <CardDescription>
          {t("The last 30 days, from the metrics module.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-baseline gap-2">
          <span className="text-3xl font-semibold tabular-nums">
            {format.number(counts.total)}
          </span>
          <span className="text-muted-foreground text-sm">
            {t("{previous} in the 30 days before", {
              previous: format.number(counts.previous),
            })}
          </span>
        </div>
        <dl className="grid grid-cols-2 gap-2 text-sm">
          {rows.map((row) => (
            <div key={row.key} className="space-y-1">
              <dt className="text-muted-foreground">{row.label}</dt>
              <dd className="font-medium tabular-nums">
                {format.number(row.value)}
              </dd>
            </div>
          ))}
        </dl>
      </CardContent>
    </Card>
  );
}

export function CustomersCardSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
