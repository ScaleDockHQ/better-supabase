import type { MoneyJson } from "better-supabase/commerce";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { ReceiptTextIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { refresh } from "next/cache";

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
import {
  Table,
  TableBody,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getPayablesAging } from "../payables-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: what the organization owes its suppliers on open
 * purchase bills, then the same total by days past due.
 */
export async function PayablesAgingSection() {
  const [state, t, format, locale] = await Promise.all([
    getPayablesAging(),
    getExtracted("payables"),
    getFormatter(),
    getLocale(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The payables didn't load")}</AlertTitle>
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

  const aging = state.data;

  if (moneyFromJson(aging.outstanding).amount === 0n) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ReceiptTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No open purchase bills")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Record a supplier's bill against its purchase order, then issue it to see what you owe here.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/invoices"
          >
            {t("Read the invoices guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const amount = (value: MoneyJson) =>
    formatMoney(moneyFromJson(value), locale);

  const asOf = format.dateTime(new Date(aging.asOf), {
    dateStyle: "medium",
    timeZone: "UTC",
  });

  const buckets = [
    { key: "current", label: t("Not yet due"), value: aging.current },
    { key: "1-30", label: t("1 to 30 days"), value: aging.days1To30 },
    { key: "31-60", label: t("31 to 60 days"), value: aging.days31To60 },
    { key: "61-90", label: t("61 to 90 days"), value: aging.days61To90 },
    { key: "90+", label: t("Over 90 days"), value: aging.over90 },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader>
            <CardDescription>{t("Outstanding")}</CardDescription>
            <CardTitle className="tabular-nums">
              {amount(aging.outstanding)}
            </CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>{t("Overdue bills")}</CardDescription>
            <CardTitle className="tabular-nums">{aging.overdueCount}</CardTitle>
          </CardHeader>
          <CardContent>
            {aging.overdueCount === 0 ? (
              <Badge variant="success-light">{t("On time")}</Badge>
            ) : (
              <Badge variant="warning-light">{t("Past due")}</Badge>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>{t("Over 90 days")}</CardDescription>
            <CardTitle className="tabular-nums">
              {amount(aging.over90)}
            </CardTitle>
          </CardHeader>
        </Card>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>{t("Aging")}</CardTitle>
          <CardDescription>
            {t("Open purchase bills by days past due on {date}.", {
              date: asOf,
            })}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Due")}</TableHead>
                <TableHead className="text-right">{t("Owed")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {buckets.map((bucket) => (
                <TableRow key={bucket.key}>
                  <TableCell className="font-medium">{bucket.label}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {amount(bucket.value)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
            <TableFooter>
              <TableRow>
                <TableCell>{t("Total")}</TableCell>
                <TableCell className="text-right tabular-nums">
                  {amount(aging.outstanding)}
                </TableCell>
              </TableRow>
            </TableFooter>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

export function PayablesAgingSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <div className="grid gap-4 md:grid-cols-3">
        <Skeleton className="h-28 rounded-xl" />
        <Skeleton className="h-28 rounded-xl" />
        <Skeleton className="h-28 rounded-xl" />
      </div>
      <Skeleton className="h-72 rounded-xl" />
    </div>
  );
}
