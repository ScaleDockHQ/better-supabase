"use client";

import { useExtracted } from "next-intl";
import { createContext, use } from "react";

import { Checkbox } from "@/components/ui/checkbox";

import type { RecordListColumns } from "./record-list-grid";
import type { RecordSelection } from "./use-record-selection";

interface SelectionScope {
  readonly selection: RecordSelection;
  /** The ids of the rows on screen, for the select-all box. */
  readonly ids: readonly string[];
}

const SelectionContext = createContext<SelectionScope | null>(null);

export const RecordSelectionProvider = SelectionContext.Provider;

function useScope(): SelectionScope {
  const scope = use(SelectionContext);

  if (scope === null) {
    throw new Error("The select column needs a RecordSelectionProvider.");
  }

  return scope;
}

function SelectHeader() {
  const t = useExtracted("recordList");
  const { selection, ids } = useScope();

  return (
    <Checkbox
      aria-label={t("Select all rows")}
      checked={ids.length > 0 && selection.count === ids.length}
      indeterminate={selection.count > 0 && selection.count < ids.length}
      onCheckedChange={(checked) => {
        selection.setAll(checked ? ids : []);
      }}
    />
  );
}

function SelectCell({
  row,
}: {
  readonly row: { readonly original: { readonly id: string } };
}) {
  const t = useExtracted("recordList");
  const { selection } = useScope();

  return (
    <Checkbox
      aria-label={t("Select row")}
      checked={selection.has(row.original.id)}
      onCheckedChange={() => {
        selection.toggle(row.original.id);
      }}
    />
  );
}

/** The leading checkbox column of a list with bulk actions. */
export function selectColumn<
  Row extends { readonly id: string },
>(): RecordListColumns<Row>[number] {
  return {
    id: "select",
    header: SelectHeader,
    cell: SelectCell,
    size: 40,
    enableSorting: false,
  };
}
