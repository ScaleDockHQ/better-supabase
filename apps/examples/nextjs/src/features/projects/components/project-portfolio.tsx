import { formatMoney } from "better-supabase/commerce";
import { BriefcaseBusinessIcon, ClockIcon, GaugeIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";

import { IntentLink } from "@/components/intent-link";
import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { approveAndInvoiceTimesheet } from "@/features/composites/composites-actions";
import { ActionButton } from "@/features/sales/components/action-button";
import {
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { loadPortfolio } from "../projects-finance";
import { ProjectLoadError } from "./project-load-error";

export function ProjectPortfolioSkeleton() {
  return (
    <div className="flex flex-col gap-6">
      <KpiBandSkeleton />
      <Skeleton className="h-64 rounded-xl" aria-busy="true" />
    </div>
  );
}

/**
 * The figures and the list of the project portfolio: how many projects there
 * are, the hours tracked this week against capacity, and each project with its
 * tracked and billable hours.
 */
// skeleton: the page's Suspense fallback is ProjectPortfolioSkeleton
export async function ProjectPortfolio() {
  await requirePermission("time_entries.read");

  const [t, locale, format, loaded] = await Promise.all([
    getExtracted("projects"),
    getLocale(),
    getFormatter(),
    loadPortfolio().then(
      (portfolio) => ({ ok: true as const, portfolio }),
      () => ({ ok: false as const }),
    ),
  ]);

  if (!loaded.ok) {
    return <ProjectLoadError title={t("The portfolio didn't load")} />;
  }

  const { portfolio } = loaded;
  const canApprove = await holds("time_entries.approve");

  if (portfolio === null) {
    return null;
  }

  const hours = (value: number) =>
    format.number(value, { maximumFractionDigits: 1 });

  return (
    <div className="flex flex-col gap-6">
      <KpiBand
        kpis={[
          {
            label: t("Projects"),
            value: String(portfolio.rows.length),
            hint: t("Not in the trash"),
            icon: <BriefcaseBusinessIcon className="size-4" />,
          },
          {
            label: t("Hours this week"),
            value: hours(portfolio.weekHours),
            hint: t("Tracked by the whole team"),
            icon: <ClockIcon className="size-4" />,
          },
          {
            label: t("Utilization"),
            value: format.number(portfolio.utilization, { style: "percent" }),
            hint: t("Against a 40 hour week per member"),
            icon: <GaugeIcon className="size-4" />,
          },
        ]}
      />
      <Card>
        <CardHeader>
          <CardTitle>{t("Projects")}</CardTitle>
          <CardDescription>
            {t("Tracked time and budget of every project.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {portfolio.rows.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <BriefcaseBusinessIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No projects yet")}</EmptyTitle>
                <EmptyDescription>
                  {t("Create one from the task views.")}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <ul className="flex flex-col divide-y">
              {portfolio.rows.map((row) => (
                <li
                  key={row.id}
                  className="flex items-center justify-between gap-3 py-2"
                >
                  <IntentLink
                    href={`/projects/${row.id}`}
                    className="truncate text-sm font-medium hover:underline"
                  >
                    {row.name}
                  </IntentLink>
                  <span className="text-sm text-muted-foreground tabular-nums">
                    {t("{hours} h tracked, {billable} h billable", {
                      hours: hours(row.hours),
                      billable: hours(row.billableHours),
                    })}
                    {" · "}
                    {formatMoney(row.budget, locale)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Time awaiting approval")}</CardTitle>
          <CardDescription>
            {t(
              "Approve a submitted week and invoice the unbilled time in one step.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {portfolio.awaiting.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No submitted week is waiting for approval.")}
            </p>
          ) : (
            <ul className="flex flex-col divide-y">
              {portfolio.awaiting.map((sheet) => (
                <li
                  key={sheet.id}
                  className="flex items-center justify-between gap-3 py-2"
                >
                  <span className="text-sm">
                    {t("Week of {week}", { week: sheet.week })}
                  </span>
                  {canApprove ? (
                    <ActionButton
                      action={approveAndInvoiceTimesheet}
                      input={{ timesheetId: sheet.id }}
                      label={t("Approve and invoice")}
                      successMessage={t("Week approved and invoiced")}
                    />
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
