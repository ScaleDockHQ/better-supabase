import { ReceiptIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
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

import { getBillingAccount } from "../billing-account-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>` and a `PermissionGate` for `billing.read`: the
 * Stripe customer, the seats and the latest invoices of the organization.
 */
export async function BillingAccount() {
  const [result, t, format] = await Promise.all([
    getBillingAccount().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("billingAccount"),
    getFormatter(),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The billing account didn't load")}</AlertTitle>
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

  const account = result.data;

  if (account === null) {
    return null;
  }

  if (account.customerId === null) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ReceiptIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No Stripe customer yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "The organization gets a Stripe customer when it first opens Checkout. Until then there are no invoices to list.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link
            href="/settings/billing"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Choose a plan")}
          </Link>
        </EmptyContent>
      </Empty>
    );
  }

  const money = (total: number | null, currency: string | null) =>
    total === null
      ? "-"
      : format.number(total / 100, {
          style: "currency",
          currency: (currency ?? "usd").toUpperCase(),
        });

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("Stripe account")}</CardTitle>
          <CardDescription>
            {t(
              "The customer and subscription Stripe holds for this organization.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm sm:grid-cols-3">
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Customer")}
            </span>
            <span className="font-mono text-xs">{account.customerId}</span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">{t("Seats")}</span>
            <span>{format.number(account.seats)}</span>
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xs text-muted-foreground">
              {t("Subscription")}
            </span>
            {account.subscriptionStatus === null ? (
              <span>{t("None")}</span>
            ) : (
              <Badge variant="info-light">{account.subscriptionStatus}</Badge>
            )}
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Invoices")}</CardTitle>
          <CardDescription>
            {t("The latest twelve invoices Stripe sent.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {account.invoices.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <ReceiptIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No invoices yet")}</EmptyTitle>
                <EmptyDescription>
                  {t("Stripe's first invoice shows up here once it is sent.")}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Number")}</TableHead>
                  <TableHead>{t("Date")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  <TableHead className="text-right">{t("Total")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {account.invoices.map((invoice) => (
                  <TableRow key={invoice.id}>
                    <TableCell>
                      {invoice.url === null ? (
                        (invoice.number ?? invoice.id)
                      ) : (
                        <a
                          href={invoice.url}
                          rel="noreferrer"
                          className="underline-offset-4 transition-colors hover:underline"
                        >
                          {invoice.number ?? invoice.id}
                        </a>
                      )}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {invoice.createdAt === null
                        ? "-"
                        : format.dateTime(new Date(invoice.createdAt), {
                            dateStyle: "medium",
                          })}
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary">{invoice.status ?? "-"}</Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {money(invoice.total, invoice.currency)}
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

export function BillingAccountSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
