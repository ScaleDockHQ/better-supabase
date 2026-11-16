import { FileTextIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";
import type { EntityListMap } from "@/lib/block-entity-page";

import { CreateQuoteDialog } from "@/features/crm/components/create-quote-dialog";
import { organizationPager } from "@/lib/block-entity-page";

import { BlockOverview } from "./block-overview";
import { holds, moneyFormatter, requirePermission } from "./overview-support";

/** The quotes list's URL names on the quotes block's page. */
const quotesMap: EntityListMap = {
  sorts: {
    newest: { by: "createdAt", direction: "desc" },
    // The block has no total sort, so the quotes that expire first come on top.
    expires: { by: "validUntil" },
    title: { by: "title" },
  },
  filters: { f: "status" },
  facets: { f: "status" },
};

/**
 * The organization's quotes, searched, filtered by status and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function QuoteOverview({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("quotes.read");

  const [t, fmtMoney, canWrite] = await Promise.all([
    getExtracted("sales"),
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
      pager={({ db, tenant }) =>
        organizationPager(tenant, {
          page: (options) => db.$blocks.quotes.page(options),
          facets: (options) => db.$blocks.quotes.facets(options),
        })
      }
      map={quotesMap}
      query={query}
      toRow={(quote) => ({
        id: quote.id,
        quote:
          quote.revision > 1
            ? `${quote.identifier} rev. ${String(quote.revision)}`
            : quote.identifier,
        title: quote.title,
        status: quote.status,
        total: fmtMoney(quote.totals.total),
        validUntil: quote.validUntil?.toString() ?? null,
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
        { value: "expires", label: t("Expiring soonest") },
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
