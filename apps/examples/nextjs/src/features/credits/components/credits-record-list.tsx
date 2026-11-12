"use client";

import { CoinsIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { dateCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";
import { Link } from "@/i18n/navigation";

import type { CreditEntryRow } from "../credits-list";

import { creditList } from "../credits-list";

function MemoCell({ row }: { row: { original: CreditEntryRow } }) {
  const t = useExtracted("credits");
  const { transactionId, memo } = row.original;

  return (
    <Link
      href={`/settings/billing/credits/${transactionId}`}
      prefetch
      className="truncate font-medium hover:underline"
    >
      {memo ?? t("No description")}
    </Link>
  );
}

function AmountCell({ row }: { row: { original: CreditEntryRow } }) {
  const format = useFormatter();
  const { amount } = row.original;

  return (
    <span
      className={
        amount < 0
          ? "text-destructive tabular-nums"
          : "text-success tabular-nums"
      }
    >
      {format.number(amount, { signDisplay: "exceptZero" })}
    </span>
  );
}

/** The credit ledger on the list kit. */
export function CreditRecordList({
  initial,
}: {
  initial: RecordListPage<CreditEntryRow>;
}) {
  const t = useExtracted("credits");

  const labels = new Map([
    ["credit.grant", t("Plan grant")],
    ["credit.purchase", t("Purchase")],
    ["credit.usage", t("Usage")],
  ]);

  const columns: RecordListColumns<CreditEntryRow> = [
    { id: "memo", header: t("Description"), size: 280, cell: MemoCell },
    {
      id: "kind",
      header: t("Type"),
      size: 130,
      cell: ({ row }) => labels.get(row.original.kind) ?? row.original.kind,
    },
    { id: "amount", header: t("Credits"), size: 110, cell: AmountCell },
    { accessorKey: "reference", header: t("Reference"), size: 160 },
    {
      id: "effective",
      header: t("Date"),
      size: 180,
      cell: dateCell<CreditEntryRow>((row) => row.effectiveAt),
    },
  ];

  return (
    <AdminRecordList
      list={creditList}
      endpoint="/api/credits/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "kind",
          label: t("Type"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search credit entries")}
      emptyIcon={<CoinsIcon />}
      emptyTitle={t("No credit entries found")}
      emptyDescription={t(
        "Credits appear when the plan grants them, when you buy more and when work uses them.",
      )}
    />
  );
}
