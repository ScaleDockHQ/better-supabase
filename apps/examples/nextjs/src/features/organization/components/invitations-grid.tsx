"use client";

import type { ReactNode } from "react";

import { MailIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useRouter } from "next/navigation";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";

import { RecordListGrid } from "@/components/record-list/record-list-grid";
import { Button } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

import type { InvitationRow } from "../organization-invitations";

function renderEmail({ row }: { row: { original: InvitationRow } }): ReactNode {
  return <span className="font-medium">{row.original.email}</span>;
}

function ExpiresCell({ expiresAt }: { expiresAt: string | null }): ReactNode {
  const format = useFormatter();

  if (expiresAt === null) {
    return "–";
  }

  return (
    <span className="tabular-nums">
      {format.dateTime(new Date(expiresAt), {
        dateStyle: "medium",
        timeZone: "UTC",
      })}
    </span>
  );
}

function renderExpires({
  row,
}: {
  row: { original: InvitationRow };
}): ReactNode {
  return <ExpiresCell expiresAt={row.original.expiresAt} />;
}

/**
 * The open invitations in the read-only grid; `rows` is `null` when the read
 * failed.
 */
export function InvitationsGrid({
  rows,
}: {
  rows: readonly InvitationRow[] | null;
}) {
  const t = useExtracted("organization");
  const router = useRouter();

  const columns: RecordListColumns<InvitationRow> = [
    {
      id: "email",
      accessorKey: "email",
      header: t("Email"),
      cell: renderEmail,
    },
    { id: "role", accessorKey: "role", header: t("Role") },
    { id: "expiresAt", header: t("Expires"), cell: renderExpires },
  ];

  return (
    <RecordListGrid
      rows={rows ?? []}
      columns={columns}
      failed={rows === null}
      pending={false}
      emptyIcon={<MailIcon />}
      emptyTitle={t("No open invitations")}
      emptyDescription={t("Invite people from the members page.")}
      emptyAction={
        <Button
          variant="outline"
          nativeButton={false}
          render={<Link href="/settings/members" />}
        >
          {t("Open members")}
        </Button>
      }
      onRetry={() => {
        router.refresh();
      }}
    />
  );
}
