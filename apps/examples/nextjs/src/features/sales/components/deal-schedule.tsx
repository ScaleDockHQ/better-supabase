import type { CSSProperties } from "react";

import {
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { Temporal } from "temporal-polyfill";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link } from "@/i18n/navigation";

import type { DealRow } from "../pipeline/pipeline-queries";

import { loadDeals } from "../pipeline/pipeline-queries";
import { moneyFormatter, requirePermission } from "./overview-support";

/** Deals shown in one calendar day before the rest fold into a count. */
const DAY_LIMIT = 3;

export function DealCalendarSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

export function DealTimelineSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}

function monthOf(value: string | undefined): Temporal.PlainYearMonth {
  if (value !== undefined && /^\d{4}-\d{2}$/u.test(value)) {
    try {
      return Temporal.PlainYearMonth.from(value);
    } catch {
      // A month outside the calendar falls back to the current one.
    }
  }

  return Temporal.Now.plainDateISO().toPlainYearMonth();
}

/** A plain date as a `Date` at noon UTC, so no zone moves it to another day. */
function noonUtc(date: Temporal.PlainDate): Date {
  return new Date(Date.UTC(date.year, date.month - 1, date.day, 12));
}

/** The width of a bar: `amount` as a share of `largest`, at least 2 percent. */
function barShare(amount: bigint, largest: bigint): string {
  return `${Math.max(2, Number((amount * 100n) / largest))}%`;
}

const badgeFor = (category: string) =>
  category === "won"
    ? "success-light"
    : category === "lost"
      ? "destructive-light"
      : "primary-light";

/** The deals of the default pipeline on a month grid, by expected close date. */
export async function DealCalendar({
  month: requested,
}: {
  month: string | undefined;
}) {
  await requirePermission("deals.read");

  const [t, loaded, format] = await Promise.all([
    getExtracted("sales"),
    settle(loadDeals),
    getFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The calendar didn't load")} />;
  }

  const month = monthOf(requested);
  const first = month.toPlainDate({ day: 1 });
  const lead = first.dayOfWeek - 1;
  const cells = Math.ceil((lead + month.daysInMonth) / 7) * 7;
  const today = Temporal.Now.plainDateISO();

  const byDay = new Map<string, DealRow[]>();

  for (const deal of loaded.data?.deals ?? []) {
    byDay.set(deal.closeOn, [...(byDay.get(deal.closeOn) ?? []), deal]);
  }

  const days = Array.from({ length: cells }, (_, index) =>
    first.add({ days: index - lead }),
  );

  const link = (target: Temporal.PlainYearMonth) =>
    `/crm/deals?tab=calendar&month=${target.toString()}` as const;

  const weekdays = days
    .slice(0, 7)
    .map((day) => ({
      key: day.toString(),
      label: format.dateTime(noonUtc(day), {
        weekday: "short",
        timeZone: "UTC",
      }),
    }));

  return (
    <section
      aria-label={t("Deal calendar")}
      className="flex flex-col gap-3"
      data-testid="deal-calendar"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-medium">
          {format.dateTime(noonUtc(first), {
            month: "long",
            year: "numeric",
            timeZone: "UTC",
          })}
        </h2>
        <nav aria-label={t("Months")} className="flex gap-1">
          <Link
            href={link(month.subtract({ months: 1 }))}
            aria-label={t("Previous month")}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
          >
            <ChevronLeftIcon />
          </Link>
          <Link
            href={link(today.toPlainYearMonth())}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Today")}
          </Link>
          <Link
            href={link(month.add({ months: 1 }))}
            aria-label={t("Next month")}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
          >
            <ChevronRightIcon />
          </Link>
        </nav>
      </div>
      <div className="overflow-x-auto rounded-xl border">
        <div className="grid min-w-176 grid-cols-7 text-sm">
          {weekdays.map((weekday) => (
            <div
              key={weekday.key}
              className="border-b px-2 py-1 text-xs text-muted-foreground"
            >
              {weekday.label}
            </div>
          ))}
          {days.map((day) => {
            const key = day.toString();
            const deals = byDay.get(key) ?? [];
            const inMonth = day.month === month.month;

            return (
              <div
                key={key}
                className="flex min-h-24 flex-col gap-1 border-r border-b p-1 last:border-r-0 data-[outside=true]:bg-muted/40"
                data-outside={!inMonth}
              >
                <span
                  className={
                    day.equals(today)
                      ? "w-fit rounded-full bg-primary px-1.5 text-xs text-primary-foreground"
                      : "px-1 text-xs text-muted-foreground"
                  }
                >
                  {day.day}
                </span>
                {deals.slice(0, DAY_LIMIT).map((deal) => (
                  <Link
                    key={deal.id}
                    href={`/crm/deals/${deal.id}`}
                    className="truncate rounded-sm bg-accent px-1 py-0.5 text-xs transition-colors hover:bg-accent/70"
                    title={deal.name}
                  >
                    {deal.name}
                  </Link>
                ))}
                {deals.length > DAY_LIMIT ? (
                  <span className="px-1 text-xs text-muted-foreground">
                    {t("+{count} more", {
                      count: String(deals.length - DAY_LIMIT),
                    })}
                  </span>
                ) : null}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/**
 * The open deals grouped by the month they should close, with each amount as a
 * bar.
 */
export async function DealTimeline() {
  await requirePermission("deals.read");

  const [t, loaded, fmtMoney, format] = await Promise.all([
    getExtracted("sales"),
    settle(loadDeals),
    moneyFormatter(),
    getFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The timeline didn't load")} />;
  }

  const open = (loaded.data?.deals ?? [])
    .filter((deal) => deal.category === "open")
    .toSorted((a, b) => a.closeOn.localeCompare(b.closeOn));

  if (open.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <CalendarDaysIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No open deals")}</EmptyTitle>
          <EmptyDescription>
            {t("Open deals appear here by the month they should close.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const groups = new Map<string, DealRow[]>();

  for (const deal of open) {
    const key = deal.closeOn.slice(0, 7);

    groups.set(key, [...(groups.get(key) ?? []), deal]);
  }

  const largest = open.reduce(
    (max, deal) => (deal.amount.amount > max ? deal.amount.amount : max),
    1n,
  );

  const today = Temporal.Now.plainDateISO();

  return (
    <section
      aria-label={t("Deal timeline")}
      className="flex flex-col gap-6"
      data-testid="deal-timeline"
    >
      {[...groups.entries()].map(([key, deals]) => {
        const month = Temporal.PlainYearMonth.from(key);

        return (
          <div key={key} className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">
              {format.dateTime(noonUtc(month.toPlainDate({ day: 1 })), {
                month: "long",
                year: "numeric",
                timeZone: "UTC",
              })}
              <span className="ml-2 text-xs font-normal text-muted-foreground">
                {t("{count, plural, one {# deal} other {# deals}}", {
                  count: deals.length,
                })}
              </span>
            </h2>
            <ul className="flex flex-col gap-1 rounded-xl border p-2">
              {deals.map((deal) => {
                const late =
                  Temporal.PlainDate.compare(
                    Temporal.PlainDate.from(deal.closeOn),
                    today,
                  ) < 0;

                return (
                  <li
                    key={deal.id}
                    className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 px-1 py-1 text-sm sm:grid-cols-[12rem_minmax(0,1fr)_auto_auto]"
                  >
                    <Link
                      href={`/crm/deals/${deal.id}`}
                      className="truncate font-medium hover:underline"
                    >
                      {deal.name}
                    </Link>
                    <div
                      className="hidden h-2 rounded-full bg-muted sm:block"
                      aria-hidden
                    >
                      <div
                        className="h-2 w-(--bar) rounded-full bg-primary"
                        // SAFETY: CSSProperties does not list custom properties, which are valid style keys.
                        style={
                          {
                            "--bar": barShare(deal.amount.amount, largest),
                          } as CSSProperties
                        }
                      />
                    </div>
                    <span className="text-xs text-muted-foreground tabular-nums">
                      {fmtMoney(deal.amount)}
                    </span>
                    <Badge
                      variant={late ? "warning-light" : badgeFor(deal.category)}
                    >
                      {late ? t("Overdue") : deal.stage}
                    </Badge>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
    </section>
  );
}
