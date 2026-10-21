import type { InvoiceStatus } from "better-supabase/blocks/invoices";

import { formatMoney } from "better-supabase/commerce";
import { FileTextIcon, TriangleAlertIcon } from "lucide-react";
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
  CardAction,
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getInvoices } from "../invoice-queries";
import {
  CreateDraftInvoiceDialog,
  IssueInvoiceButton,
} from "./invoice-controls";

// #region recipe:invoices-table
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: the organization's invoices with their status,
 * total and what's still owed. Renders nothing without `invoices.read`, so the
 * billing page still shows the plan.
 */
export async function InvoicesTable() {
  const session = await getSession();

  if (!can(session, "invoices.read")) {
    return null;
  }

  const [list, t, format, locale] = await Promise.all([
    getInvoices(),
    getExtracted("billing"),
    getFormatter(),
    getLocale(),
  ]);

  if (list.kind === "no-organization") {
    return null;
  }

  const canWrite = can(session, "invoices.write");

  const status = (value: InvoiceStatus, overdue: boolean) => {
    if (overdue) {
      return <Badge variant="destructive-light">{t("Overdue")}</Badge>;
    }

    switch (value) {
      case "draft": {
        return <Badge variant="secondary">{t("Draft")}</Badge>;
      }

      case "issued": {
        return <Badge variant="info-light">{t("Issued")}</Badge>;
      }

      case "partially_paid": {
        return <Badge variant="warning-light">{t("Partly paid")}</Badge>;
      }

      case "paid": {
        return <Badge variant="success-light">{t("Paid")}</Badge>;
      }

      case "void": {
        return <Badge variant="outline">{t("Void")}</Badge>;
      }

      case "uncollectible": {
        return <Badge variant="destructive-light">{t("Uncollectible")}</Badge>;
      }

      default: {
        const unknown: never = value;

        return unknown;
      }
    }
  };

  const hasInvoices = list.kind === "ok" && list.invoices.length > 0;

  return (
    <Card data-recipe="invoices-table">
      <CardHeader>
        <CardTitle>{t("Invoices")}</CardTitle>
        <CardDescription>
          {t("Every invoice for this organization, newest first.")}
        </CardDescription>
        {hasInvoices && canWrite ? (
          <CardAction>
            <CreateDraftInvoiceDialog variant="outline" />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {list.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The invoices didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : list.invoices.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileTextIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No invoices yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Invoices show up here once they're created.")}
              </EmptyDescription>
            </EmptyHeader>
            {canWrite ? (
              <EmptyContent>
                <CreateDraftInvoiceDialog />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Invoice")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead>{t("Due")}</TableHead>
                <TableHead className="text-right">{t("Total")}</TableHead>
                <TableHead className="text-right">{t("Owed")}</TableHead>
                {canWrite ? (
                  <TableHead>
                    <span className="sr-only">{t("Actions")}</span>
                  </TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {list.invoices.map((invoice) => (
                <TableRow key={invoice.id}>
                  <TableCell>
                    <div className="flex flex-col gap-1">
                      <span className="text-sm">{invoice.title}</span>
                      <span className="font-mono text-xs text-muted-foreground">
                        {invoice.identifier ?? t("No number yet")}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell>
                    {status(invoice.status, invoice.overdue)}
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {invoice.dueOn
                      ? format.dateTime(new Date(invoice.dueOn), {
                          dateStyle: "medium",
                          timeZone: "UTC",
                        })
                      : t("Not issued")}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(invoice.total, locale)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(invoice.balance, locale)}
                  </TableCell>
                  {canWrite ? (
                    <TableCell className="text-right">
                      {invoice.status === "draft" ? (
                        <IssueInvoiceButton invoiceId={invoice.id} />
                      ) : null}
                    </TableCell>
                  ) : null}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:invoices-table

export function InvoicesTableSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
