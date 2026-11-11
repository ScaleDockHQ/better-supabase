"use client";

import type { CellContext } from "@tanstack/react-table";

import { BookmarkIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { CollectionRow } from "../collection-row";

import {
  COLLECTION_SCOPE_VALUES,
  COLLECTION_STATE_VALUES,
} from "../collections-list";
import { useCollectionListState } from "../use-collection-list-state";
import {
  CollectionScopeBadge,
  useScopeLabel,
  useStateLabel,
} from "./collection-status";
import { CreateCollectionDialog } from "./create-collection-dialog";

type CollectionCell = CellContext<ReadOnlyGridFeatures, CollectionRow>;

function NameCell({ row }: CollectionCell) {
  const { id, name, description } = row.original;

  return (
    <div className="flex flex-col">
      <Link
        href={`/shop/collections/${id}`}
        className="font-medium hover:underline"
      >
        {name}
      </Link>
      {description === null ? null : (
        <span className="truncate text-xs text-muted-foreground">
          {description}
        </span>
      )}
    </div>
  );
}

function ScopeCell({ row }: CollectionCell) {
  return (
    <CollectionScopeBadge
      scope={row.original.scope}
      archived={row.original.archived}
    />
  );
}

/** The collections overview on the list kit; the URL holds scope and state. */
export function CollectionRecordList({
  initial,
  canWrite,
}: {
  initial: RecordListPage<CollectionRow>;
  canWrite: boolean;
}) {
  const t = useExtracted("collections");
  const scopeLabel = useScopeLabel();
  const stateLabel = useStateLabel();
  const list = useCollectionListState();

  const columns: RecordListColumns<CollectionRow> = [
    { accessorKey: "name", header: t("Collection"), size: 320, cell: NameCell },
    { accessorKey: "subjectType", header: t("Holds"), size: 140 },
    {
      accessorKey: "scope",
      header: t("Shared with"),
      size: 160,
      cell: ScopeCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/collections/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "scope",
          label: t("Shared with"),
          valueLabel: scopeLabel,
          values: COLLECTION_SCOPE_VALUES,
        },
        {
          key: "state",
          label: t("State"),
          valueLabel: stateLabel,
          values: COLLECTION_STATE_VALUES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<BookmarkIcon />}
      emptyTitle={t("No collections found")}
      emptyDescription={
        canWrite
          ? t("Create a collection, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canWrite ? <CreateCollectionDialog /> : null}
    />
  );
}
