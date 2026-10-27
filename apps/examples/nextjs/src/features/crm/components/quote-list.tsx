import { formatMoney } from "better-supabase/commerce";
import { FileTextIcon } from "lucide-react";
import { getExtracted, getLocale } from "next-intl/server";
import { forbidden } from "next/navigation";

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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadQuotes, settle } from "../crm-queries";
import { CreateQuoteDialog } from "./create-quote-dialog";
import { CrmLoadError } from "./crm-load-error";
import { QuoteStatusBadge } from "./quote-status-badge";

/** Render inside `<Suspense>`: the organization's latest quotes. */
export async function QuoteList() {
  const [t, locale, permissions] = await Promise.all([
    getExtracted("crm"),
    getLocale(),
    getPermissions(),
  ]);

  if (!can(permissions, "quotes.read")) {
    forbidden();
  }

  const quotes = await settle(loadQuotes);

  if (quotes.kind === "no-organization") {
    return null;
  }

  if (quotes.kind === "error") {
    return <CrmLoadError title={t("The quotes didn't load")} />;
  }

  if (quotes.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No quotes yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Write a quote with line items and send it for acceptance.")}
          </EmptyDescription>
        </EmptyHeader>
        {can(permissions, "quotes.write") ? (
          <EmptyContent>
            <CreateQuoteDialog />
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Quotes")}</CardTitle>
        <CardDescription>
          {t("{count, plural, one {# quote} other {# quotes}}", {
            count: quotes.data.length,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("Quote")}</TableHead>
              <TableHead>{t("Title")}</TableHead>
              <TableHead>{t("Status")}</TableHead>
              <TableHead className="text-right">{t("Total")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {quotes.data.map((quote) => (
              <TableRow key={quote.id}>
                <TableCell>
                  <Link
                    href={`/crm/quotes/${quote.id}`}
                    className="font-medium tabular-nums hover:underline"
                  >
                    {quote.revision > 1
                      ? t("{identifier} rev. {revision, number}", {
                          identifier: quote.identifier,
                          revision: quote.revision,
                        })
                      : quote.identifier}
                  </Link>
                </TableCell>
                <TableCell>{quote.title}</TableCell>
                <TableCell>
                  <QuoteStatusBadge status={quote.status} />
                </TableCell>
                <TableCell className="text-right tabular-nums">
                  {formatMoney(quote.total, locale)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export function QuoteListSkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
