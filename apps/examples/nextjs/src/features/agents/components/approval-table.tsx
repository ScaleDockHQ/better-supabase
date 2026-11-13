"use client";

import type { CellContext } from "@tanstack/react-table";

import { useAction, useErrorMessage } from "better-supabase/react";
import { CheckIcon, InboxIcon, XIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { createContext, use, useMemo, useState } from "react";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Link } from "@/i18n/navigation";
import { toast } from "@/lib/toast";

import type { PendingApprovalRow } from "../agents-queries";

import { decideApprovals } from "../agents-actions";

interface Selection {
  readonly selected: ReadonlySet<string>;
  readonly toggle: (approvalId: string) => void;
}

const SelectionContext = createContext<Selection>({
  selected: new Set(),
  toggle: () => undefined,
});

type ApprovalCell = CellContext<ReadOnlyGridFeatures, ApprovalRow>;

/** The grid needs an `id`; an approval's own id is the row id. */
interface ApprovalRow extends PendingApprovalRow {
  readonly id: string;
}

function SelectCell({ row }: ApprovalCell) {
  const t = useExtracted("agents");
  const { selected, toggle } = use(SelectionContext);
  const { id, tool } = row.original;

  return (
    <Checkbox
      checked={selected.has(id)}
      aria-label={t("Select {tool}", { tool })}
      onCheckedChange={() => {
        toggle(id);
      }}
    />
  );
}

function ToolCell({ row }: ApprovalCell) {
  return <Badge variant="warning-light">{row.original.tool}</Badge>;
}

function InputCell({ row }: ApprovalCell) {
  return (
    <code className="block max-w-lg truncate text-xs text-muted-foreground">
      {row.original.input}
    </code>
  );
}

function ChatCell({ row }: ApprovalCell) {
  const { chatId, chatTitle } = row.original;

  return (
    <Link href={`/assistant/${chatId}`} className="font-medium hover:underline">
      {chatTitle === "" ? chatId.slice(0, 8) : chatTitle}
    </Link>
  );
}

function AskedCell({ row }: ApprovalCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

/** The approval inbox: select rows and approve or deny them in one go. */
export function ApprovalTable({
  items,
  tools,
}: {
  items: readonly PendingApprovalRow[];
  /** The tools with a pending approval, for the filter. */
  tools: readonly string[];
}) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set());

  const rows = useMemo(
    () => items.map((item) => ({ ...item, id: item.approvalId })),
    [items],
  );

  const decide = useAction(decideApprovals, {
    onSuccess: (count) => {
      setSelected(new Set());
      toast.success(t("Decided {count, number} approvals", { count }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const context = useMemo<Selection>(
    () => ({
      selected,
      toggle: (approvalId) => {
        setSelected((current) => {
          const next = new Set(current);

          if (next.has(approvalId)) {
            next.delete(approvalId);
          } else {
            next.add(approvalId);
          }

          return next;
        });
      },
    }),
    [selected],
  );

  const columns: RecordListColumns<ApprovalRow> = [
    { id: "select", header: "", size: 40, cell: SelectCell },
    { accessorKey: "tool", header: t("Tool"), size: 160, cell: ToolCell },
    { accessorKey: "input", header: t("Input"), size: 320, cell: InputCell },
    { accessorKey: "chatTitle", header: t("Chat"), size: 220, cell: ChatCell },
    {
      accessorKey: "createdAt",
      header: t("Asked"),
      size: 170,
      cell: AskedCell,
    },
  ];

  const run = (approved: boolean) => {
    void decide.run({
      approved,
      decisions: rows
        .filter((row) => selected.has(row.id))
        .map((row) => ({ chatId: row.chatId, approvalId: row.approvalId })),
    });
  };

  return (
    <SelectionContext value={context}>
      <div className="flex flex-col gap-3">
        {selected.size === 0 ? null : (
          <section
            className="flex items-center gap-2 rounded-lg border bg-card px-3 py-2 text-sm"
            aria-label={t("Bulk decision")}
          >
            <span className="mr-auto tabular-nums">
              {t("{count, number} selected", { count: selected.size })}
            </span>
            <Button
              size="sm"
              disabled={decide.pending}
              onClick={() => {
                run(true);
              }}
            >
              <CheckIcon />
              {t("Approve selected")}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={decide.pending}
              onClick={() => {
                run(false);
              }}
            >
              <XIcon />
              {t("Deny selected")}
            </Button>
          </section>
        )}
        <OpsList
          rows={rows}
          columns={columns}
          nextCursor={null}
          filter={{
            label: t("Every tool"),
            options: tools.map((tool) => ({ value: tool, label: tool })),
          }}
          sorts={[{ value: "newest", label: t("Newest first") }]}
          searchLabel={t("Search by chat")}
          emptyIcon={<InboxIcon />}
          emptyTitle={t("Nothing to approve")}
          emptyDescription={t("Tool calls that need a decision show up here.")}
        />
      </div>
    </SelectionContext>
  );
}
