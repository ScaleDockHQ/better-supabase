import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { loadContacts, settle } from "@/features/crm/crm-queries";
import { ActionButton } from "@/features/sales/components/action-button";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  DetailTable,
  FactGrid,
} from "@/features/sales/components/detail-table";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";
import { loadLookups } from "@/features/warehouse/warehouse-queries";
import { Link } from "@/i18n/navigation";

import {
  addRfqLine,
  awardRfq,
  cancelRfq,
  declineInvitation,
  inviteSupplier,
  recordQuote,
  transitionRfq,
  withdrawQuote,
} from "../rfqs-actions";
import { loadRfq } from "../rfqs-queries";
import { rfqStatusLabels } from "./rfqs-overview";

export function RfqDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

const TONE = new Map<
  string,
  | "info-light"
  | "warning-light"
  | "success-light"
  | "destructive-light"
  | "secondary"
>([
  ["open", "info-light"],
  ["closed", "warning-light"],
  ["awarded", "success-light"],
  ["cancelled", "destructive-light"],
  ["draft", "secondary"],
]);

/**
 * A request with its lines, suppliers, quotes and the comparison that ends in
 * an award.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function RfqDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("rfqs.read");

  const [
    t,
    loaded,
    fmtDate,
    fmtMoney,
    statuses,
    contacts,
    lookups,
    canWrite,
    canManage,
  ] = await Promise.all([
    getExtracted("rfqs"),
    settle(() => loadRfq(id)),
    dateFormatter(),
    moneyFormatter(),
    rfqStatusLabels(),
    settle(loadContacts),
    settle(loadLookups),
    holds("rfqs.write"),
    holds("rfqs.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The request didn't load")} />;
  }

  const rfq = loaded.data;

  if (!rfq) {
    notFound();
  }

  const invitable =
    contacts.kind === "ok"
      ? contacts.data.filter(
          (row) =>
            row.kind === "company" &&
            row.supplierStatus !== "blocked" &&
            !rfq.suppliers.some((supplier) => supplier.supplierId === row.id),
        )
      : [];

  const locations = lookups.kind === "ok" ? lookups.data.locations : [];

  const live = rfq.status === "open" || rfq.status === "closed";

  const hasQuotes = rfq.compare.quotes.length > 0;

  const quoteStatus = new Map([
    ["submitted", t("Submitted")],
    ["withdrawn", t("Withdrawn")],
    ["awarded", t("Awarded")],
    ["rejected", t("Rejected")],
  ]);

  const supplierStatus = new Map([
    ["invited", t("Invited")],
    ["quoted", t("Quoted")],
    ["declined", t("Declined")],
  ]);

  const awardFields = [
    {
      name: "location",
      label: t("Receive at (creates a purchase order)"),
      kind: "select" as const,
      options: [
        { value: "", label: t("No purchase order") },
        ...locations.map((row) => ({ value: row.id, label: row.name })),
      ],
    },
  ];

  return (
    <RecordDetailFrame
      title={rfq.title}
      description={rfq.number}
      status={
        <Badge variant={TONE.get(rfq.status) ?? "secondary"}>
          {statuses[rfq.status]}
        </Badge>
      }
      actions={
        <>
          {canWrite && rfq.status === "draft" ? (
            <ActionButton
              action={transitionRfq}
              input={{ rfqId: rfq.id, action: "open" }}
              label={t("Send to suppliers")}
              successMessage={t("Request opened")}
              variant="default"
            />
          ) : null}
          {canWrite && rfq.status === "open" ? (
            <ActionButton
              action={transitionRfq}
              input={{ rfqId: rfq.id, action: "close" }}
              label={t("Close quoting")}
              successMessage={t("Request closed")}
            />
          ) : null}
          {canManage && live && hasQuotes ? (
            <ActionDialog
              action={awardRfq}
              title={t("Award to the cheapest quote")}
              description={t(
                "The cheapest quote that prices every line wins and the others are rejected.",
              )}
              trigger={t("Award best quote")}
              submitLabel={t("Award")}
              successMessage={t("Request awarded")}
              hidden={{ rfqId: rfq.id }}
              fields={awardFields}
            />
          ) : null}
          {canManage &&
          rfq.status !== "awarded" &&
          rfq.status !== "cancelled" ? (
            <ActionDialog
              action={cancelRfq}
              title={t("Cancel request")}
              trigger={t("Cancel request")}
              submitLabel={t("Cancel request")}
              successMessage={t("Request cancelled")}
              variant="outline"
              hidden={{ rfqId: rfq.id }}
              fields={[
                {
                  name: "reason",
                  label: t("Reason"),
                  kind: "textarea",
                  required: true,
                },
              ]}
            />
          ) : null}
        </>
      }
    >
      <RecordDetailTabs
        base={`/rfqs/${id}`}
        active={tab}
        tabs={[
          { value: "overview", label: t("Overview") },
          { value: "suppliers", label: t("Suppliers") },
          { value: "quotes", label: t("Quotes") },
          { value: "compare", label: t("Compare") },
        ]}
      />
      {tab === "suppliers" ? (
        <DetailTable
          title={t("Suppliers")}
          description={t("Invited suppliers answer with a quote or decline.")}
          action={
            canWrite && (rfq.status === "draft" || rfq.status === "open") ? (
              <ActionDialog
                action={inviteSupplier}
                title={t("Invite a supplier")}
                trigger={t("Invite supplier")}
                submitLabel={t("Invite")}
                successMessage={t("Supplier invited")}
                variant="outline"
                hidden={{ rfqId: rfq.id }}
                fields={[
                  {
                    name: "supplierId",
                    label: t("Supplier"),
                    kind: "select",
                    options: invitable.map((row) => ({
                      value: row.id,
                      label: row.name,
                    })),
                  },
                ]}
              />
            ) : undefined
          }
          head={[t("Supplier"), t("Status"), t("Invited"), t("Answered"), ""]}
          rows={rfq.suppliers.map((supplier) => ({
            key: supplier.id,
            cells: [
              <Link
                key="name"
                href={`/crm/contacts/${supplier.supplierId}`}
                className="font-medium hover:underline"
              >
                {supplier.name}
              </Link>,
              supplierStatus.get(supplier.status) ?? supplier.status,
              fmtDate(supplier.invitedAt),
              fmtDate(supplier.respondedAt),
              canWrite && rfq.status === "open" ? (
                <div key="actions" className="flex gap-2">
                  <ActionDialog
                    action={recordQuote}
                    title={t("Record a quote from {supplier}", {
                      supplier: supplier.name,
                    })}
                    description={t(
                      "Enter the unit price per line in {currency}. A new quote replaces the earlier one.",
                      { currency: rfq.currency },
                    )}
                    trigger={t("Record quote")}
                    submitLabel={t("Save quote")}
                    successMessage={t("Quote recorded")}
                    variant="outline"
                    hidden={{
                      rfqId: rfq.id,
                      invitationId: supplier.id,
                      currency: rfq.currency,
                    }}
                    fields={[
                      ...rfq.lines.map((line) => ({
                        name: `line_${line.id}`,
                        label: `${line.description} (${line.quantity})`,
                        kind: "decimal" as const,
                        required: true,
                      })),
                      {
                        name: "leadTimeDays",
                        label: t("Lead time (days)"),
                        kind: "number" as const,
                      },
                    ]}
                  />
                  {supplier.status === "invited" ? (
                    <ActionButton
                      action={declineInvitation}
                      input={{ invitationId: supplier.id }}
                      label={t("Declined")}
                      successMessage={t("Invitation declined")}
                    />
                  ) : null}
                </div>
              ) : null,
            ],
          }))}
          emptyTitle={t("No suppliers invited")}
          emptyDescription={t("Invite at least one supplier before sending.")}
        />
      ) : tab === "quotes" ? (
        <DetailTable
          title={t("Quotes")}
          head={[
            t("Supplier"),
            t("Total"),
            t("Lead time"),
            t("Valid until"),
            t("Revision"),
            t("Status"),
            "",
          ]}
          rows={rfq.quotes.map((quote) => ({
            key: quote.id,
            cells: [
              quote.supplier,
              fmtMoney(quote.total),
              quote.leadTimeDays === null
                ? "–"
                : t("{days} days", { days: String(quote.leadTimeDays) }),
              fmtDate(quote.validUntil),
              String(quote.revision),
              <Badge
                key="status"
                variant={
                  quote.status === "awarded" ? "success-light" : "secondary"
                }
              >
                {quoteStatus.get(quote.status) ?? quote.status}
              </Badge>,
              canWrite &&
              rfq.status === "open" &&
              quote.status === "submitted" ? (
                <ActionButton
                  key="withdraw"
                  action={withdrawQuote}
                  input={{ quoteId: quote.id }}
                  label={t("Withdraw")}
                  successMessage={t("Quote withdrawn")}
                />
              ) : null,
            ],
          }))}
          emptyTitle={t("No quotes yet")}
          emptyDescription={t(
            "Record a quote for each supplier that answers once the request is open.",
          )}
        />
      ) : tab === "compare" ? (
        <DetailTable
          title={t("Comparison")}
          description={t("The cheapest price per line is marked.")}
          head={[
            t("Line"),
            ...rfq.compare.quotes.map(
              (quote) =>
                `${quote.supplier}${quote.lowest ? ` (${t("cheapest")})` : ""}`,
            ),
          ]}
          rows={[
            ...rfq.compare.lines.map((line) => ({
              key: line.lineId,
              cells: [
                `${line.description} × ${line.quantity}`,
                ...rfq.compare.quotes.map((quote) => {
                  const offer = line.offers.find(
                    (row) => row.quoteId === quote.quoteId,
                  );

                  return offer ? (
                    <span
                      key={quote.quoteId}
                      className={offer.lowest ? "font-semibold" : undefined}
                    >
                      {fmtMoney(offer.unitAmount)}
                    </span>
                  ) : (
                    "–"
                  );
                }),
              ],
            })),
            ...(hasQuotes
              ? [
                  {
                    key: "total",
                    cells: [
                      t("Total"),
                      ...rfq.compare.quotes.map((quote) =>
                        quote.complete ? (
                          <div
                            key={quote.quoteId}
                            className="flex items-center gap-2"
                          >
                            <span className="font-semibold">
                              {fmtMoney(quote.total)}
                            </span>
                            {canManage && live ? (
                              <ActionDialog
                                action={awardRfq}
                                title={t("Award to {supplier}", {
                                  supplier: quote.supplier,
                                })}
                                trigger={t("Award")}
                                submitLabel={t("Award")}
                                successMessage={t("Request awarded")}
                                variant="outline"
                                hidden={{
                                  rfqId: rfq.id,
                                  quoteId: quote.quoteId,
                                }}
                                fields={awardFields}
                              />
                            ) : null}
                          </div>
                        ) : (
                          t("Incomplete")
                        ),
                      ),
                    ],
                  },
                ]
              : []),
          ]}
          emptyTitle={t("Nothing to compare")}
          emptyDescription={t(
            "The comparison appears once a supplier has quoted.",
          )}
        />
      ) : (
        <>
          <FactGrid
            facts={[
              { label: t("Currency"), value: rfq.currency },
              { label: t("Quotes due by"), value: fmtDate(rfq.dueAt) },
              { label: t("Sent"), value: fmtDate(rfq.openedAt) },
              { label: t("Awarded"), value: fmtDate(rfq.awardedAt) },
              {
                label: t("Purchase order"),
                value: rfq.purchaseOrderId
                  ? rfq.purchaseOrderId.slice(0, 8)
                  : "–",
              },
              {
                label: t("Notes"),
                value: rfq.notes ?? rfq.cancelReason ?? "–",
              },
            ]}
          />
          <DetailTable
            title={t("Lines")}
            description={t("Every supplier prices these lines.")}
            action={
              canWrite && rfq.status === "draft" ? (
                <ActionDialog
                  action={addRfqLine}
                  title={t("Add a line")}
                  trigger={t("Add line")}
                  submitLabel={t("Add")}
                  successMessage={t("Line added")}
                  variant="outline"
                  hidden={{ rfqId: rfq.id }}
                  fields={[
                    {
                      name: "description",
                      label: t("Description"),
                      kind: "text",
                      required: true,
                    },
                    {
                      name: "quantity",
                      label: t("Quantity"),
                      kind: "number",
                      required: true,
                      defaultValue: "1",
                    },
                  ]}
                />
              ) : undefined
            }
            head={[t("Line"), t("Description"), t("Quantity")]}
            rows={rfq.lines.map((line) => ({
              key: line.id,
              cells: [
                String(line.ordinal),
                line.description,
                `${line.quantity}${line.unit ? ` ${line.unit}` : ""}`,
              ],
            }))}
            emptyTitle={t("No lines")}
            emptyDescription={t(
              "A request needs at least one line before it can be sent.",
            )}
          />
        </>
      )}
    </RecordDetailFrame>
  );
}
