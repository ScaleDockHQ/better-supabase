import { formatMoney } from "better-supabase/commerce";
import { getExtracted, getLocale } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { loadQuote, settle } from "../crm-queries";
import { CrmLoadError } from "./crm-load-error";
import { QuoteLinesEditor } from "./quote-lines-editor";
import { QuoteStatusActions } from "./quote-status-actions";
import { QuoteStatusBadge } from "./quote-status-badge";

// #region recipe:quote-builder
/**
 * Render inside `<Suspense>`: a quote's line items and totals. A draft (or
 * a quote with changes requested) is editable; the status decides what
 * comes next: send, record the customer's answer, or revise.
 */
export async function QuoteBuilder({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [{ id }, session, t, locale] = await Promise.all([
    params,
    getSession(),
    getExtracted("crm"),
    getLocale(),
  ]);

  if (!can(session, "quotes.read")) {
    forbidden();
  }

  const loaded = await settle(() => loadQuote(id));

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The quote didn't load")} />;
  }

  const quote = loaded.data;

  if (!quote) {
    notFound();
  }

  const canWrite = can(session, "quotes.write");

  const editable =
    canWrite &&
    (quote.status === "draft" || quote.status === "changes_requested");

  const totals = [
    { label: t("Subtotal"), value: quote.subtotal },
    { label: t("Discount"), value: quote.discountTotal },
    { label: t("Tax"), value: quote.taxTotal },
  ];

  return (
    <Card data-recipe="quote-builder">
      <CardHeader>
        <CardTitle>{quote.title}</CardTitle>
        <CardDescription className="flex flex-wrap items-center gap-2">
          <span className="tabular-nums">
            {t("{identifier} rev. {revision, number}", {
              identifier: quote.identifier,
              revision: quote.revision,
            })}
          </span>
          <QuoteStatusBadge status={quote.status} />
          {quote.validUntil ? (
            <span>
              {t("Valid until {date}", {
                date: Temporal.PlainDate.from(quote.validUntil).toLocaleString(
                  locale,
                  { dateStyle: "medium" },
                ),
              })}
            </span>
          ) : null}
        </CardDescription>
        {canWrite ? (
          <CardAction>
            <QuoteStatusActions
              quoteId={quote.id}
              status={quote.status}
              hasLines={quote.lines.length > 0}
            />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {editable ? (
          <QuoteLinesEditor
            key={quote.lines
              .map((line) => `${line.description}:${line.unitAmount.amount}`)
              .join(",")}
            quoteId={quote.id}
            currency={quote.currency}
            initialLines={quote.lines}
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Description")}</TableHead>
                <TableHead className="text-right">{t("Qty")}</TableHead>
                <TableHead className="text-right">{t("Unit price")}</TableHead>
                <TableHead className="text-right">{t("Discount %")}</TableHead>
                <TableHead className="text-right">{t("Tax %")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {quote.lines.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={5}
                    className="text-center text-sm text-muted-foreground"
                  >
                    {t("This quote has no lines.")}
                  </TableCell>
                </TableRow>
              ) : null}
              {quote.lines.map((line) => (
                <TableRow key={line.position}>
                  <TableCell>{line.description}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {line.quantity}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(line.unitAmount, locale)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {line.discountBps / 100}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {line.taxRateBps / 100}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <CardFooter className="justify-end">
        <dl className="grid w-full max-w-xs grid-cols-[1fr_auto] gap-x-6 gap-y-1 text-sm">
          {totals.map((total) => (
            <div key={total.label} className="contents">
              <dt className="text-muted-foreground">{total.label}</dt>
              <dd className="text-right tabular-nums">
                {formatMoney(total.value, locale)}
              </dd>
            </div>
          ))}
          <dt className="font-semibold">{t("Total")}</dt>
          <dd className="text-right font-semibold tabular-nums">
            {formatMoney(quote.total, locale)}
          </dd>
        </dl>
      </CardFooter>
    </Card>
  );
}
// #endregion recipe:quote-builder

export function QuoteBuilderSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
