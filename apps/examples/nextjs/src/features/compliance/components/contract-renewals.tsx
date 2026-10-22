import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { FileSignatureIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
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
import { Link } from "@/i18n/navigation";

import type { RenewalRow } from "../compliance-queries";

import { getRenewals } from "../compliance-queries";

// #region recipe:contract-renewals
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type Translate = Awaited<ReturnType<typeof getExtracted>>;

const SOON_DAYS = 30;

function RenewalBadge({ row, t }: { row: RenewalRow; t: Translate }) {
  const days = row.noticeInDays;

  if (days === null) {
    return <Badge variant="secondary">{t("No end date")}</Badge>;
  }

  if (days < 0) {
    return (
      <Badge variant="destructive-light">
        {row.autoRenew ? t("Renews, notice passed") : t("Notice passed")}
      </Badge>
    );
  }

  if (days <= SOON_DAYS) {
    return (
      <Badge variant="warning-light">
        {t("Notice in {days, number} days", { days })}
      </Badge>
    );
  }

  return row.autoRenew ? (
    <Badge variant="info-light">{t("Auto-renews")}</Badge>
  ) : (
    <Badge variant="success-light">{t("Active")}</Badge>
  );
}

/**
 * Render inside `<Suspense>`: the organization's active contracts, the nearest
 * notice deadline first, so the team decides on a renewal before the
 * counterparty's notice period runs out.
 */
export async function ContractRenewals() {
  const [state, t, format, locale] = await Promise.all([
    getRenewals(),
    getExtracted("compliance"),
    getFormatter(),
    getLocale(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  const day = (date: string) =>
    format.dateTime(new Date(date), { dateStyle: "medium", timeZone: "UTC" });

  return (
    <Card data-recipe="contract-renewals">
      <CardHeader>
        <CardTitle>{t("Contract renewals")}</CardTitle>
        <CardDescription>
          {t(
            "Active contracts, the nearest notice deadline first. A contract that auto-renews extends itself unless someone gives notice before the deadline.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The contracts didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : state.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileSignatureIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No active contracts")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "A contract becomes active once every signer has signed. Draft one from a customer's record.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link href="/customers" className={buttonVariants()}>
                {t("Open customers")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Contract")}</TableHead>
                <TableHead className="text-right">{t("Value")}</TableHead>
                <TableHead>{t("Ends")}</TableHead>
                <TableHead>{t("Notice by")}</TableHead>
                <TableHead>{t("Renewal")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {state.data.map((row) => (
                <TableRow key={row.id}>
                  <TableCell className="font-medium">{row.title}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {row.value
                      ? formatMoney(moneyFromJson(row.value), locale)
                      : "–"}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {row.endsOn ? day(row.endsOn) : "–"}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {row.noticeDeadline ? day(row.noticeDeadline) : "–"}
                  </TableCell>
                  <TableCell>
                    <RenewalBadge row={row} t={t} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function ContractRenewalsSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:contract-renewals
