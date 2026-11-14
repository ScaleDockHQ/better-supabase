import { FileTextIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { CreateQuoteDialog } from "@/features/crm/components/create-quote-dialog";
import { loadQuotes, settle } from "@/features/crm/crm-queries";

import { BlockOverview } from "./block-overview";
import { holds, moneyFormatter, requirePermission } from "./overview-support";

/**
 * The organization's quotes, searched, filtered by status and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function QuoteOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("quotes.read");

  const [t, loaded, fmtMoney, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(loadQuotes),
    moneyFormatter(),
    holds("quotes.write"),
  ]);

  const statuses = {
    draft: t("Draft"),
    sent: t("Sent"),
    viewed: t("Viewed"),
    accepted: t("Accepted"),
    rejected: t("Rejected"),
    changes_requested: t("Changes requested"),
    expired: t("Expired"),
    withdrawn: t("Withdrawn"),
  };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (quote) => `${quote.identifier} ${quote.title}`,
        facet: (quote) => quote.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.identifier.localeCompare(a.identifier),
          total: (a, b) => Number(b.total.amount - a.total.amount),
          title: (a, b) => a.title.localeCompare(b.title),
        },
      }}
      toRow={(quote) => ({
        id: quote.id,
        quote:
          quote.revision > 1
            ? `${quote.identifier} rev. ${String(quote.revision)}`
            : quote.identifier,
        title: quote.title,
        status: quote.status,
        total: fmtMoney(quote.total),
        validUntil: quote.validUntil,
      })}
      columns={[
        {
          key: "quote",
          header: t("Quote"),
          kind: "link",
          href: "/crm/quotes/{id}",
          size: 140,
        },
        { key: "title", header: t("Title"), kind: "text", size: 280 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 160,
          labels: statuses,
          tones: {
            draft: "secondary",
            sent: "info-light",
            viewed: "info-light",
            accepted: "success-light",
            rejected: "destructive-light",
            changes_requested: "warning-light",
          },
        },
        { key: "total", header: t("Total"), kind: "number", size: 130 },
        {
          key: "validUntil",
          header: t("Valid until"),
          kind: "muted",
          size: 130,
        },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "total", label: t("Highest total") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search quotes")}
      errorTitle={t("The quotes didn't load")}
      emptyIcon={<FileTextIcon />}
      emptyTitle={t("No quotes yet")}
      emptyDescription={t(
        "Write a quote with line items and send it for acceptance.",
      )}
      emptyAction={canWrite ? <CreateQuoteDialog /> : undefined}
    />
  );
}
