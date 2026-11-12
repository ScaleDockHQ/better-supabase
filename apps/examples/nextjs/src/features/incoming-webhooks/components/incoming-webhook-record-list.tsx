"use client";

import type { CellContext } from "@tanstack/react-table";

import { WebhookIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { IncomingWebhookRow } from "../incoming-webhooks-list";

import { incomingWebhookList } from "../incoming-webhooks-list";
import {
  CreateIncomingWebhookDialog,
  IncomingWebhookActions,
} from "./incoming-webhook-controls";

type WebhookCell = CellContext<ReadOnlyGridFeatures, IncomingWebhookRow>;

function LastReceivedCell({ row }: WebhookCell) {
  const format = useFormatter();
  const { lastReceivedAt, lastStatus } = row.original;

  return (
    <span className="text-xs text-muted-foreground">
      {lastReceivedAt
        ? `${format.dateTime(new Date(lastReceivedAt), { dateStyle: "medium", timeStyle: "short" })}${lastStatus === null ? "" : ` (${String(lastStatus)})`}`
        : "–"}
    </span>
  );
}

function ActionsCell({ row }: WebhookCell) {
  const { id, name, enabled } = row.original;

  return <IncomingWebhookActions id={id} name={name} enabled={enabled} />;
}

/** The incoming webhooks overview on the list kit. */
export function IncomingWebhookRecordList({
  initial,
  canManage,
}: {
  initial: RecordListPage<IncomingWebhookRow>;
  canManage: boolean;
}) {
  const t = useExtracted("incomingWebhooks");

  const columns: RecordListColumns<IncomingWebhookRow> = [
    { accessorKey: "name", header: t("Name"), size: 240 },
    { accessorKey: "verify", header: t("Verification"), size: 170 },
    { accessorKey: "receiveCount", header: t("Received"), size: 100 },
    {
      id: "last",
      header: t("Last delivery"),
      size: 220,
      cell: LastReceivedCell,
    },
    ...(canManage
      ? [{ id: "actions", header: "", size: 140, cell: ActionsCell }]
      : []),
  ];

  const labels = new Map([
    ["enabled", t("On")],
    ["disabled", t("Off")],
    ["none", t("None")],
    ["standard-webhooks", t("Standard Webhooks")],
    ["hmac-sha256", t("HMAC SHA-256")],
    ["shared-secret", t("Shared secret")],
  ]);

  return (
    <AdminRecordList
      list={incomingWebhookList}
      endpoint="/api/incoming-webhooks/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "state",
          label: t("State"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
        {
          key: "verify",
          label: t("Verification"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search endpoints")}
      emptyIcon={<WebhookIcon />}
      emptyTitle={t("No incoming endpoints found")}
      emptyDescription={
        canManage
          ? t("Add an endpoint, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canManage ? <CreateIncomingWebhookDialog /> : undefined}
    />
  );
}
