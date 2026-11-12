"use client";

import type { CellContext } from "@tanstack/react-table";

import { BotIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { SessionRow } from "../session-row";

import { SESSION_PROTOCOLS, SESSION_STATUSES } from "../checkout-sessions-list";
import { useSessionListState } from "../use-session-list-state";
import {
  SessionStatusBadge,
  useProtocolLabel,
  useSessionStatusLabel,
} from "./session-status";

type SessionCell = CellContext<ReadOnlyGridFeatures, SessionRow>;

function BuyerCell({ row }: SessionCell) {
  const t = useExtracted("checkoutSessions");
  const { id, buyer } = row.original;

  return (
    <Link
      href={`/shop/checkout-sessions/${id}`}
      className="font-medium hover:underline"
    >
      {buyer ?? t("Buyer not given yet")}
    </Link>
  );
}

function StatusCell({ row }: SessionCell) {
  return (
    <SessionStatusBadge
      status={row.original.status}
      expired={row.original.expired}
    />
  );
}

function ProtocolCell({ row }: SessionCell) {
  const label = useProtocolLabel();

  return <span>{label(row.original.protocol)}</span>;
}

function CreatedCell({ row }: SessionCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

/** The agent checkout sessions on the list kit; the URL holds the filters. */
export function SessionRecordList({
  initial,
}: {
  initial: RecordListPage<SessionRow>;
}) {
  const t = useExtracted("checkoutSessions");
  const statusLabel = useSessionStatusLabel();
  const protocolLabel = useProtocolLabel();
  const list = useSessionListState();

  const columns: RecordListColumns<SessionRow> = [
    { accessorKey: "buyer", header: t("Buyer"), size: 260, cell: BuyerCell },
    {
      accessorKey: "protocol",
      header: t("Protocol"),
      size: 110,
      cell: ProtocolCell,
    },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    {
      accessorKey: "createdAt",
      header: t("Started"),
      size: 180,
      cell: CreatedCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/checkout-sessions/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: SESSION_STATUSES,
        },
        {
          key: "protocol",
          label: t("Protocol"),
          valueLabel: protocolLabel,
          values: SESSION_PROTOCOLS,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<BotIcon />}
      emptyTitle={t("No checkout sessions found")}
      emptyDescription={t(
        "Agents that buy through ACP or UCP open a session on a cart.",
      )}
    />
  );
}
