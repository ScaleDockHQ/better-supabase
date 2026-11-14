"use client";

import type { CellContext } from "@tanstack/react-table";

import { ShieldCheckIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { DecisionRow } from "../guardrails-queries";

type DecisionCell = CellContext<ReadOnlyGridFeatures, DecisionRow>;

function WhenCell({ row }: DecisionCell) {
  const format = useFormatter();

  return (
    <span className="tabular-nums">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function DecisionCellView({ row }: DecisionCell) {
  const { decision } = row.original;

  return (
    <Badge
      variant={
        decision === "block"
          ? "destructive-light"
          : decision === "redact"
            ? "warning-light"
            : "success-light"
      }
    >
      {decision}
    </Badge>
  );
}

function ChatCell({ row }: DecisionCell) {
  const { chatId } = row.original;

  return chatId === undefined ? (
    <span className="text-muted-foreground">–</span>
  ) : (
    <Link
      href={`/assistant/${chatId}`}
      className="font-mono text-xs hover:underline"
    >
      {chatId.slice(0, 8)}
    </Link>
  );
}

/**
 * The decision log: every check a policy ran, with why it allowed, redacted or
 * blocked.
 */
export function DecisionTable({
  items,
  nextCursor,
}: {
  items: readonly DecisionRow[];
  nextCursor: string | null;
}) {
  const t = useExtracted("guardrails");

  const columns: RecordListColumns<DecisionRow> = [
    { accessorKey: "createdAt", header: t("When"), size: 190, cell: WhenCell },
    { accessorKey: "agent", header: t("Agent"), size: 130 },
    { accessorKey: "stage", header: t("Stage"), size: 90 },
    {
      accessorKey: "decision",
      header: t("Decision"),
      size: 110,
      cell: DecisionCellView,
    },
    { accessorKey: "reasons", header: t("Reasons"), size: 260 },
    { accessorKey: "chatId", header: t("Chat"), size: 100, cell: ChatCell },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      filter={{
        label: t("Every decision"),
        options: [
          { value: "block", label: t("Blocked") },
          { value: "redact", label: t("Redacted") },
          { value: "allow", label: t("Allowed") },
          { value: "rule:injection", label: t("Rule: prompt injection") },
          { value: "rule:pii", label: t("Rule: personal data") },
          { value: "rule:topic", label: t("Rule: denied topic") },
          { value: "rule:tool_depth", label: t("Rule: tool depth") },
        ],
      }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
      ]}
      searchLabel={t("Search by agent or reason")}
      emptyIcon={<ShieldCheckIcon />}
      emptyTitle={t("No decisions yet")}
      emptyDescription={t(
        "A check logs a decision once a policy applies to a request.",
      )}
    />
  );
}
