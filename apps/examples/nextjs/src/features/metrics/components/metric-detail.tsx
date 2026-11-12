import { TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { notFound } from "next/navigation";

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
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getCustomersMetric } from "../metrics-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** One metric over 90 days, per week and split by its dimension. */
export async function MetricDetail({ metricKey }: { metricKey: string }) {
  if (metricKey !== "customers") {
    notFound();
  }

  const [result, t, format] = await Promise.all([
    getCustomersMetric().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("metrics"),
    getFormatter(),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The metric didn't load")}</AlertTitle>
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

  const metric = result.data;

  if (metric === null) {
    return null;
  }

  return (
    <div className="grid gap-6">
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("New customers, last 90 days")}</CardTitle>
          <CardDescription>
            {t("{previous} in the 90 days before", {
              previous: format.number(metric.previous),
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex items-center gap-3">
          <span className="text-3xl font-semibold tracking-tight tabular-nums">
            {format.number(metric.value)}
          </span>
          {metric.change === null ? null : (
            <Badge
              variant={
                metric.change >= 0 ? "success-light" : "destructive-light"
              }
            >
              {format.number(metric.change, {
                style: "percent",
                signDisplay: "exceptZero",
              })}
            </Badge>
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("By week and status")}</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Week of")}</TableHead>
                <TableHead className="text-right">{t("Total")}</TableHead>
                {metric.groupNames.map((name) => (
                  <TableHead key={name} className="text-right capitalize">
                    {name === "" ? t("No status") : name}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {metric.weeks.map((week) => (
                <TableRow key={week.start}>
                  <TableCell>
                    {format.dateTime(new Date(week.start), {
                      dateStyle: "medium",
                    })}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {format.number(week.value)}
                  </TableCell>
                  {metric.groupNames.map((name) => (
                    <TableCell key={name} className="text-right tabular-nums">
                      {format.number(week.groups[name] ?? 0)}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

export function MetricDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
