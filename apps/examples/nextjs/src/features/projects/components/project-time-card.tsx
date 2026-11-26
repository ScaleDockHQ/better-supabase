import { formatMoney } from "better-supabase/commerce";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { holds } from "@/features/sales/components/overview-support";

import { getProjectFinance } from "../projects-finance";

export function ProjectTimeCardSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}

/**
 * The time tracked on a project against its budget, from the `projects`
 * composite.
 */
// skeleton: the page's Suspense fallback is ProjectTimeCardSkeleton
export async function ProjectTimeCard({ id }: { id: string }) {
  if (!(await holds("time_entries.read"))) {
    return null;
  }

  const [t, locale, format, finance] = await Promise.all([
    getExtracted("projects"),
    getLocale(),
    getFormatter(),
    getProjectFinance(id),
  ]);

  if (!finance) {
    return null;
  }

  const hours = (value: number) =>
    format.number(value, { maximumFractionDigits: 1 });

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Time and budget")}</CardTitle>
        <CardDescription>
          {t("{count, plural, one {# entry} other {# entries}} tracked", {
            count: finance.entries,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
          <dt className="text-muted-foreground">{t("Tracked")}</dt>
          <dd>{t("{hours} h", { hours: hours(finance.hours) })}</dd>
          <dt className="text-muted-foreground">{t("Billable")}</dt>
          <dd>{t("{hours} h", { hours: hours(finance.billableHours) })}</dd>
          <dt className="text-muted-foreground">{t("Billable value")}</dt>
          <dd>
            {finance.billable.length === 0
              ? t("None yet")
              : finance.billable
                  .map((amount) => formatMoney(amount, locale))
                  .join(", ")}
          </dd>
          <dt className="text-muted-foreground">{t("Budget left")}</dt>
          <dd className="flex items-center gap-2">
            {finance.remaining === null
              ? t("No budget set")
              : formatMoney(finance.remaining, locale)}
            {finance.exhausted ? (
              <Badge variant="destructive-light">{t("Used up")}</Badge>
            ) : null}
          </dd>
        </dl>
      </CardContent>
    </Card>
  );
}
