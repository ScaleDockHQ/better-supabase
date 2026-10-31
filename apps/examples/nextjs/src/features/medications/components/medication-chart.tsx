import type { MedicationAdministrationStatus } from "better-supabase/blocks/medications";

import { PillIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { connection } from "next/server";

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

import { getCustomerChart } from "../medications-queries";

// #region recipe:medication-chart
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const DOSE_VARIANT = {
  planned: "secondary",
  given: "success-light",
  refused: "warning-light",
  skipped: "outline",
  missed: "destructive-light",
} as const satisfies Record<MedicationAdministrationStatus, string>;

/**
 * Render inside `<Suspense>`: today's medication chart of a record, an order
 * per row with its dose and route and each of today's doses with its status.
 * Members with `medications.read` and read access to the record see it.
 */
export async function MedicationChart({
  clientId,
}: { clientId?: string } = {}) {
  await connection();

  const [state, t, format] = await Promise.all([
    getCustomerChart(clientId),
    getExtracted("medications"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="medication-chart">
        <TriangleAlertIcon />
        <AlertTitle>{t("The medication chart didn't load")}</AlertTitle>
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

  const chart = state.data;

  if (chart === "no-customer" || chart.orders.length === 0) {
    return (
      <Empty className="border" data-recipe="medication-chart">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <PillIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No medication today")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Add a medication to the list, then prescribe it for a customer with a dose and a schedule.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/medications"
          >
            {t("Read the medications guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const label = (status: MedicationAdministrationStatus) => {
    switch (status) {
      case "planned": {
        return t("Planned");
      }

      case "given": {
        return t("Given");
      }

      case "refused": {
        return t("Refused");
      }

      case "skipped": {
        return t("Skipped");
      }

      case "missed": {
        return t("Missed");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const time = (instant: string) =>
    format.dateTime(new Date(instant), { timeStyle: "short", timeZone: "UTC" });

  return (
    <Card data-recipe="medication-chart">
      <CardHeader>
        <CardTitle>
          {t("Medication for {customer}", { customer: chart.customer })}
        </CardTitle>
        <CardDescription>
          {t("Today's orders and the status of each dose.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {chart.orders.map((order) => (
          <div
            key={order.id}
            className="flex flex-col gap-2 border-b pb-4 last:border-b-0 last:pb-0"
          >
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm font-medium">{order.medication}</span>
              <span className="text-sm text-muted-foreground">
                {order.route ? `${order.dose}, ${order.route}` : order.dose}
              </span>
              {order.asNeeded ? (
                <Badge variant="info-light">{t("As needed")}</Badge>
              ) : null}
              {order.highRisk ? (
                <Badge variant="warning-light">{t("Double check")}</Badge>
              ) : null}
              {order.paused ? (
                <Badge variant="secondary">{t("Paused")}</Badge>
              ) : null}
            </div>
            {order.doses.length > 0 ? (
              <div className="flex flex-wrap gap-1">
                {order.doses.map((dose) => (
                  <Badge key={dose.id} variant={DOSE_VARIANT[dose.status]}>
                    {dose.at ? `${time(dose.at)} ` : ""}
                    {label(dose.status)}
                  </Badge>
                ))}
              </div>
            ) : (
              <span className="text-xs text-muted-foreground">
                {t("No doses today")}
              </span>
            )}
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function MedicationChartSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
// #endregion recipe:medication-chart
