"use client";

import { ShieldAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { Badge } from "@/components/reui/badge";
import { dateCell, listCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";
import { Link } from "@/i18n/navigation";

import type { SecurityStreamRow } from "../security-events-list";

import { securityStreamList } from "../security-events-list";

function StatusCell({ row }: { row: { original: SecurityStreamRow } }) {
  const t = useExtracted("securityEvents");
  const { status } = row.original;

  return (
    <Badge variant={status === "enabled" ? "success-light" : "secondary"}>
      {status === "enabled"
        ? t("Enabled")
        : status === "paused"
          ? t("Paused")
          : t("Disabled")}
    </Badge>
  );
}

function ReceiverCell({ row }: { row: { original: SecurityStreamRow } }) {
  const { id, receiver } = row.original;

  return (
    <Link
      href={`/settings/security/events/${id}`}
      prefetch
      className="truncate font-medium hover:underline"
    >
      {receiver}
    </Link>
  );
}

function DeliveryCell({ row }: { row: { original: SecurityStreamRow } }) {
  const t = useExtracted("securityEvents");

  return (
    <span className="text-xs text-muted-foreground">
      {row.original.delivery === "push" ? t("Push") : t("Poll")}
    </span>
  );
}

/** Security events on the list kit. */
export function SecurityStreamRecordList({
  initial,
}: {
  initial: RecordListPage<SecurityStreamRow>;
}) {
  const t = useExtracted("securityEvents");

  const columns: RecordListColumns<SecurityStreamRow> = [
    { id: "receiver", header: t("Receiver"), size: 240, cell: ReceiverCell },
    { id: "status", header: t("State"), size: 120, cell: StatusCell },
    { id: "delivery", header: t("Delivery"), size: 110, cell: DeliveryCell },
    {
      id: "events",
      header: t("Events"),
      size: 260,
      cell: listCell<SecurityStreamRow>((row) => row.events),
    },
    {
      id: "verified",
      header: t("Verified"),
      size: 180,
      cell: dateCell<SecurityStreamRow>((row) => row.verifiedAt),
    },
  ];

  const labels = new Map([
    ["enabled", t("Enabled")],
    ["paused", t("Paused")],
    ["disabled", t("Disabled")],
    ["push", t("Push")],
    ["poll", t("Poll")],
  ]);

  return (
    <AdminRecordList
      list={securityStreamList}
      endpoint="/api/security-events/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("State"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
        {
          key: "delivery",
          label: t("Delivery"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search receivers")}
      emptyIcon={<ShieldAlertIcon />}
      emptyTitle={t("No streams found")}
      emptyDescription={t(
        "Receivers register a stream to get security event tokens; change the filters to see more.",
      )}
    />
  );
}
