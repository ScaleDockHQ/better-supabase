"use client";

import type { CellContext } from "@tanstack/react-table";

import { MessageSquareIcon, PinIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { ChatRow } from "../assistant-queries";

type ChatCell = CellContext<ReadOnlyGridFeatures, ChatRow>;

function TitleCell({ row }: ChatCell) {
  const t = useExtracted("assistant");
  const { id, title, pinned } = row.original;

  return (
    <Link
      href={`/assistant/${id}`}
      prefetch
      className="flex items-center gap-2 font-medium hover:underline"
    >
      {pinned ? <PinIcon className="size-3.5" aria-hidden /> : null}
      <span className="truncate">
        {title === "" ? t("Untitled chat") : title}
      </span>
    </Link>
  );
}

function ModelCell({ row }: ChatCell) {
  const { model } = row.original;

  return model === undefined ? (
    <span className="text-muted-foreground">–</span>
  ) : (
    <Badge variant="secondary">{model}</Badge>
  );
}

function LastMessageCell({ row }: ChatCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.lastMessageAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

/** The chats overview: the URL holds the search, the filter and the page. */
export function ChatTable({
  items,
  nextCursor,
}: {
  items: readonly ChatRow[];
  nextCursor: string | null;
}) {
  const t = useExtracted("assistant");

  const columns: RecordListColumns<ChatRow> = [
    { accessorKey: "title", header: t("Chat"), size: 360, cell: TitleCell },
    { accessorKey: "model", header: t("Model"), size: 220, cell: ModelCell },
    {
      accessorKey: "lastMessageAt",
      header: t("Last message"),
      size: 200,
      cell: LastMessageCell,
    },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      filter={{
        label: t("All chats"),
        options: [
          { value: "pinned", label: t("Pinned") },
          { value: "archived", label: t("Archived") },
        ],
      }}
      sorts={[{ value: "recent", label: t("Most recent") }]}
      searchLabel={t("Search chats")}
      emptyIcon={<MessageSquareIcon />}
      emptyTitle={t("No chats found")}
      emptyDescription={t("Start a chat above, or change the search.")}
    />
  );
}
