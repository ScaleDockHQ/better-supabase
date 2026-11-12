import { FileQuestionIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { BlockOverview } from "@/features/sales/components/block-overview";
import {
  dateFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { createRfq } from "../rfqs-actions";
import { loadRfqs } from "../rfqs-queries";

export function RfqListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}

export async function rfqStatusLabels(): Promise<Record<string, string>> {
  const t = await getExtracted("rfqs");

  return {
    draft: t("Draft"),
    open: t("Open"),
    closed: t("Closed"),
    awarded: t("Awarded"),
    cancelled: t("Cancelled"),
  };
}

/**
 * Requests for quotation, searched, filtered by status, sorted and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function RfqOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("rfqs.read");

  const [t, loaded, fmtDate, statuses] = await Promise.all([
    getExtracted("rfqs"),
    settle(loadRfqs),
    dateFormatter(),
    rfqStatusLabels(),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (rfq) => `${rfq.number} ${rfq.title}`,
        facet: (rfq) => rfq.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.createdAt.localeCompare(a.createdAt),
          due: (a, b) => (a.dueAt ?? "9999").localeCompare(b.dueAt ?? "9999"),
          title: (a, b) => a.title.localeCompare(b.title),
        },
      }}
      toRow={(rfq) => ({
        id: rfq.id,
        number: rfq.number,
        title: rfq.title,
        currency: rfq.currency,
        status: rfq.status,
        dueAt: fmtDate(rfq.dueAt),
        createdAt: fmtDate(rfq.createdAt),
      })}
      columns={[
        { key: "number", header: t("Number"), kind: "muted", size: 110 },
        {
          key: "title",
          header: t("Request"),
          kind: "link",
          href: "/rfqs/{id}",
          size: 300,
        },
        { key: "currency", header: t("Currency"), kind: "muted", size: 90 },
        { key: "dueAt", header: t("Due"), kind: "muted", size: 130 },
        { key: "createdAt", header: t("Created"), kind: "muted", size: 130 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: statuses,
          tones: {
            open: "info-light",
            closed: "warning-light",
            awarded: "success-light",
            cancelled: "destructive-light",
          },
        },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "due", label: t("Soonest due") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search requests")}
      errorTitle={t("The requests didn't load")}
      emptyIcon={<FileQuestionIcon />}
      emptyTitle={t("No requests found")}
      emptyDescription={t(
        "Ask suppliers to quote on the same lines, compare the answers and award one, or change the filters.",
      )}
    />
  );
}

// skeleton: renders from props and translations, so nothing of its own suspends
export async function CreateRfqDialog() {
  const t = await getExtracted("rfqs");

  return (
    <ActionDialog
      action={createRfq}
      title={t("New request")}
      description={t(
        "A draft request gets the next RFQ number. Add its first line now and the rest on the request.",
      )}
      trigger={t("New request")}
      submitLabel={t("Create request")}
      successMessage={t("Request created")}
      redirectTo="/rfqs/{id}"
      fields={[
        { name: "title", label: t("Title"), kind: "text", required: true },
        {
          name: "currency",
          label: t("Currency"),
          kind: "select",
          options: [
            { value: "EUR", label: "EUR" },
            { value: "USD", label: "USD" },
            { value: "GBP", label: "GBP" },
          ],
        },
        { name: "dueOn", label: t("Quotes due by"), kind: "date" },
        { name: "description", label: t("First line"), kind: "text" },
        {
          name: "quantity",
          label: t("Quantity"),
          kind: "number",
          defaultValue: "1",
        },
        { name: "notes", label: t("Notes"), kind: "textarea" },
      ]}
    />
  );
}
