import type { ReactNode } from "react";

import { getExtracted, getLocale } from "next-intl/server";

import type {
  BlockColumn,
  BlockRow,
} from "@/components/record-list/block-list-view";
import type { BlockRowInput } from "@/components/record-list/money-text";
import type { Loaded } from "@/features/crm/crm-queries";
import type { BlockListQuery, BlockListSpec } from "@/lib/array-list";

import { BlockListView } from "@/components/record-list/block-list-view";
import { withMoneyCells } from "@/components/record-list/money-text";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { applyBlockList } from "@/lib/array-list";

export type { BlockColumn, BlockRow };

/**
 * The server half of a block-backed overview: it takes the loaded items, runs
 * the URL's search, facet filter, sort and page over them, and hands the client
 * grid one page of plain rows. Render it inside `<Suspense>`.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function BlockOverview<Item>({
  loaded,
  query,
  spec,
  toRow,
  columns,
  facet,
  sorts,
  searchLabel,
  errorTitle,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  loaded: Loaded<readonly Item[]>;
  query: BlockListQuery;
  spec: BlockListSpec<Item>;
  toRow: (item: Item) => BlockRowInput;
  columns: readonly BlockColumn[];
  facet?: {
    readonly key: string;
    readonly label: string;
    readonly values: Readonly<Record<string, string>>;
  };
  sorts: readonly { readonly value: string; readonly label: string }[];
  searchLabel: string;
  errorTitle: string;
  emptyIcon: ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  emptyAction?: ReactNode;
}) {
  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={errorTitle} />;
  }

  const t = await getExtracted("sales");
  const locale = await getLocale();
  const result = applyBlockList(loaded.data, query, spec);

  const facetOptions = facet
    ? Object.entries(facet.values)
        .map(([value, label]) => ({
          value,
          label,
          count: result.facetCounts[value] ?? 0,
        }))
        .filter((option) => option.count > 0 || option.value === query.facet)
    : undefined;

  return (
    <div className="flex flex-col gap-2">
      <BlockListView
        rows={result.rows.map((item) =>
          withMoneyCells(toRow(item), columns, locale),
        )}
        columns={columns}
        {...(facet && facetOptions
          ? { facetKey: facet.key, facetLabel: facet.label, facetOptions }
          : {})}
        sorts={sorts}
        searchLabel={searchLabel}
        total={result.total}
        page={result.page}
        pages={result.pages}
        emptyIcon={emptyIcon}
        emptyTitle={emptyTitle}
        emptyDescription={emptyDescription}
        emptyAction={emptyAction}
      />
      <p className="text-xs text-muted-foreground">
        {t("{count} in total", { count: String(result.total) })}
      </p>
    </div>
  );
}
