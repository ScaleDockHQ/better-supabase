import { BellRingIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
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
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { holds } from "@/features/sales/components/overview-support";

import { getCollections } from "../dunning-queries";
import { ApplyStandardLevels } from "./apply-standard-levels";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the reminder levels overdue sales invoices climb
 * and the latest reminder runs, for the collections side of receivables.
 */
export async function CollectionsSection() {
  const [state, t, format, canManage] = await Promise.all([
    getCollections(),
    getExtracted("finance"),
    getFormatter(),
    holds("invoices.manage"),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("Collections didn't load")}</AlertTitle>
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

  const { levels, runs } = state.data;

  if (levels.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BellRingIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No reminder levels yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Reminder levels decide when an overdue invoice gets a reminder and what fee it adds.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        {canManage ? (
          <EmptyContent>
            <ApplyStandardLevels />
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  const fee = (minor: number) =>
    minor === 0
      ? t("No fee")
      : format.number(minor / 100, { minimumFractionDigits: 2 });

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Reminder levels")}</CardTitle>
          <CardDescription>
            {t("An overdue sales invoice climbs a level at each step.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Level")}</TableHead>
                <TableHead>{t("Days after due")}</TableHead>
                <TableHead>{t("Fee")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {levels.map((level) => (
                <TableRow key={level.level}>
                  <TableCell>
                    <span className="flex items-center gap-2 tabular-nums">
                      {level.level}
                      {level.final ? (
                        <Badge variant="warning-light">
                          {t("Final notice")}
                        </Badge>
                      ) : null}
                    </span>
                  </TableCell>
                  <TableCell className="tabular-nums">
                    {level.daysAfterDue}
                  </TableCell>
                  <TableCell className="tabular-nums">
                    {fee(level.fee)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Reminder runs")}</CardTitle>
          <CardDescription>
            {t("The daily job raises each overdue invoice to its level.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {runs.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No run has picked an invoice yet.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("As of")}</TableHead>
                  <TableHead>{t("Invoices")}</TableHead>
                  <TableHead>{t("Customers")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {runs.map((run) => (
                  <TableRow key={run.id}>
                    <TableCell className="tabular-nums">
                      {format.dateTime(new Date(run.asOf), {
                        dateStyle: "medium",
                        timeZone: "UTC",
                      })}
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {run.invoices}
                    </TableCell>
                    <TableCell className="tabular-nums">
                      {run.customers}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export function CollectionsSectionSkeleton() {
  return (
    <div className="grid gap-4 lg:grid-cols-2" aria-busy="true">
      <Skeleton className="h-56 rounded-xl" />
      <Skeleton className="h-56 rounded-xl" />
    </div>
  );
}
