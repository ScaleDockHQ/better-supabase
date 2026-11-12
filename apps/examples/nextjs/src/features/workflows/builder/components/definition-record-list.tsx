"use client";

import type { CellContext } from "@tanstack/react-table";

import { useAction, useErrorMessage } from "better-supabase/react";
import { Trash2Icon, WorkflowIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useSimpleListState } from "@/components/record-list/use-simple-list-state";
import { Badge } from "@/components/reui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";
import { toast } from "@/lib/toast";

import type { DefinitionListRow, DefinitionState } from "../../workflow-lists";

import { DEFINITION_STATES, definitionList } from "../../workflow-lists";
import { removeDefinition } from "../builder-actions";

type Cell = CellContext<ReadOnlyGridFeatures, DefinitionListRow>;

const STATE_BADGE = {
  published: "success-light",
  draft: "info-light",
  new: "secondary",
} as const satisfies Record<DefinitionState, string>;

function useStateLabel() {
  const t = useExtracted("workflows");

  return (state: string): string => {
    switch (state) {
      case "published": {
        return t("Published");
      }

      case "draft": {
        return t("Draft");
      }

      default: {
        return t("Not saved yet");
      }
    }
  };
}

function NameCell({ row }: Cell) {
  const { id, name, slug } = row.original;

  return (
    <Link
      href={`/workflows/builder/${id}`}
      prefetch
      className="flex flex-col font-medium hover:underline"
    >
      {name}
      <span className="font-mono text-xs font-normal text-muted-foreground">
        {slug}
      </span>
    </Link>
  );
}

function StateCell({ row }: Cell) {
  const label = useStateLabel();
  const { state, published } = row.original;

  return (
    <span className="flex items-center gap-2">
      <Badge variant={STATE_BADGE[state]}>{label(state)}</Badge>
      {published === null ? null : (
        <span className="text-xs text-muted-foreground tabular-nums">
          v{published}
        </span>
      )}
    </span>
  );
}

function UpdatedCell({ row }: Cell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.updatedAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function RemoveCell({ row }: Cell) {
  const t = useExtracted("workflows");
  const errorMessage = useErrorMessage();
  const { id, name } = row.original;

  const remove = useAction(removeDefinition, {
    onSuccess: () => {
      toast.success(t("Workflow deleted"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("Delete {name}", { name })}
          />
        }
      >
        <Trash2Icon />
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Delete {name}?", { name })}</AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "Its versions and triggers go with it. Runs already started keep their history.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={remove.pending}
            onClick={() => {
              void remove.run({ id });
            }}
          >
            {t("Delete")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/**
 * The definitions overview on the list kit: the URL holds the search, the state
 * filter, the sort and the page, and the list route serves every state but the
 * default, which the server renders.
 */
export function DefinitionRecordList({
  initial,
}: {
  initial: RecordListPage<DefinitionListRow>;
}) {
  const t = useExtracted("workflows");
  const stateLabel = useStateLabel();
  const list = useSimpleListState(definitionList);

  const columns: RecordListColumns<DefinitionListRow> = [
    { accessorKey: "name", header: t("Workflow"), size: 340, cell: NameCell },
    { accessorKey: "state", header: t("State"), size: 180, cell: StateCell },
    {
      accessorKey: "updatedAt",
      header: t("Updated"),
      size: 200,
      cell: UpdatedCell,
    },
    { id: "actions", header: "", size: 60, cell: RemoveCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/workflows/definitions/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "state",
          label: t("State"),
          valueLabel: stateLabel,
          values: DEFINITION_STATES,
        },
      ]}
      sorts={[
        { value: "updated", label: t("Recently updated") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search workflows")}
      emptyIcon={<WorkflowIcon />}
      emptyTitle={t("No workflows found")}
      emptyDescription={t(
        "Create one above, start from a template, or change the filters.",
      )}
      emptyAction={
        <Link
          href="/workflows/templates"
          className="text-sm text-primary hover:underline"
        >
          {t("Browse templates")}
        </Link>
      }
    />
  );
}
