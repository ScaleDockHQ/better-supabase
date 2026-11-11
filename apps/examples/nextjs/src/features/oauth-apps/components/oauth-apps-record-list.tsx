"use client";

import { KeyRoundIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { dateCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { OAuthAppRow } from "../oauth-apps-list";

import { oauthAppList } from "../oauth-apps-list";

/** OAuth apps on the list kit. */
export function OAuthAppRecordList({
  initial,
}: {
  initial: RecordListPage<OAuthAppRow>;
}) {
  const t = useExtracted("oauthApps");

  const columns: RecordListColumns<OAuthAppRow> = [
    { accessorKey: "name", header: t("Name"), size: 220 },
    { accessorKey: "type", header: t("Type"), size: 130 },
    { accessorKey: "registration", header: t("Registration"), size: 130 },
    { accessorKey: "redirectUris", header: t("Redirect URIs"), size: 320 },
    {
      id: "created",
      header: t("Created"),
      size: 180,
      cell: dateCell<OAuthAppRow>((row) => row.createdAt),
    },
  ];

  const labels = new Map([
    ["public", t("Public")],
    ["confidential", t("Confidential")],
    ["dynamic", t("Dynamic")],
    ["manual", t("Manual")],
  ]);

  return (
    <AdminRecordList
      list={oauthAppList}
      endpoint="/api/oauth-apps/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "type",
          label: t("Type"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
        {
          key: "registration",
          label: t("Registration"),
          valueLabel: (value) => labels.get(value) ?? value,
        },
      ]}
      searchLabel={t("Search apps")}
      emptyIcon={<KeyRoundIcon />}
      emptyTitle={t("No OAuth apps found")}
      emptyDescription={t(
        "Register an OAuth client in the Supabase Auth settings, or change the filters.",
      )}
    />
  );
}
