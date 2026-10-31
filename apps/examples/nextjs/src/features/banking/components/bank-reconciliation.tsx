import type { MoneyJson } from "better-supabase/commerce";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { BanknoteIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getBankReconciliation } from "../banking-queries";
import { BankTransactionGrid } from "./bank-transaction-grid";

// #region recipe:bank-reconciliation
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/**
 * Render inside `<Suspense>`: each bank account's statement balance and what is
 * left to match, then its latest transactions with a suggested invoice for each
 * unmatched one.
 */
export async function BankReconciliation() {
  const [state, permissions, t, locale] = await Promise.all([
    getBankReconciliation(),
    getPermissions(),
    getExtracted("banking"),
    getLocale(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="bank-reconciliation">
        <TriangleAlertIcon />
        <AlertTitle>{t("The bank accounts didn't load")}</AlertTitle>
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

  if (state.data.length === 0) {
    return (
      <Empty className="border" data-recipe="bank-reconciliation">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BanknoteIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No bank accounts yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Add a bank account with its IBAN, then import a camt.053 or MT940 statement to start matching.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/banking"
          >
            {t("Read the banking guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const amount = (value: MoneyJson) =>
    formatMoney(moneyFromJson(value), locale);

  const canReconcile = can(permissions, "banking.reconcile");

  return (
    <div className="flex flex-col gap-8" data-recipe="bank-reconciliation">
      {state.data.map((account) => (
        <section key={account.id} className="flex flex-col gap-4">
          <div className="grid gap-4 md:grid-cols-3">
            <Card>
              <CardHeader>
                <CardDescription>{t("Statement balance")}</CardDescription>
                <CardTitle>
                  {account.statementBalance === null
                    ? "–"
                    : amount(account.statementBalance)}
                </CardTitle>
              </CardHeader>
              <CardContent>
                {account.reconciled ? (
                  <Badge variant="success-light">{t("Reconciled")}</Badge>
                ) : (
                  <Badge variant="warning-light">{t("Open")}</Badge>
                )}
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardDescription>{t("Left to match")}</CardDescription>
                <CardTitle>{amount(account.unmatchedTotal)}</CardTitle>
              </CardHeader>
              <CardContent className="text-sm text-muted-foreground">
                {t(
                  "{count, plural, one {# transaction} other {# transactions}}",
                  { count: account.unmatchedCount },
                )}
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardDescription>
                  {t("Difference with the books")}
                </CardDescription>
                <CardTitle>
                  {account.difference === null
                    ? "–"
                    : amount(account.difference)}
                </CardTitle>
              </CardHeader>
            </Card>
          </div>
          <Frame spacing="sm">
            <FrameHeader className="gap-0.5">
              <FrameTitle>{account.name}</FrameTitle>
              <FrameDescription>
                {account.iban ?? t("The latest transactions on this account.")}
              </FrameDescription>
            </FrameHeader>
            <FramePanel>
              {account.transactions.length === 0 ? (
                <Empty>
                  <EmptyHeader>
                    <EmptyTitle>{t("No transactions yet")}</EmptyTitle>
                    <EmptyDescription>
                      {t(
                        "Import a statement or sync a bank feed; a transaction seen before is skipped.",
                      )}
                    </EmptyDescription>
                  </EmptyHeader>
                  <EmptyContent>
                    <a
                      className="text-sm underline underline-offset-4"
                      href="https://bettersupabase.com/docs/blocks/banking"
                    >
                      {t("Read how to import statements")}
                    </a>
                  </EmptyContent>
                </Empty>
              ) : (
                <BankTransactionGrid
                  transactions={account.transactions}
                  canReconcile={canReconcile}
                />
              )}
            </FramePanel>
          </Frame>
        </section>
      ))}
    </div>
  );
}

export function BankReconciliationSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <div className="grid gap-4 md:grid-cols-3">
        <Skeleton className="h-28 rounded-xl" />
        <Skeleton className="h-28 rounded-xl" />
        <Skeleton className="h-28 rounded-xl" />
      </div>
      <Frame spacing="sm">
        <FrameHeader className="gap-1">
          <Skeleton className="h-4 w-36" />
          <Skeleton className="h-4 w-64" />
        </FrameHeader>
        <FramePanel>
          <Skeleton className="h-48" />
        </FramePanel>
      </Frame>
    </div>
  );
}
// #endregion recipe:bank-reconciliation
