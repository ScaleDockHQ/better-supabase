import type { CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { entityPageIndexes, resolveEntityPages } from "../gen/entity-pages.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

/**
 * Whether an index leads with `column`, after the tenant column when it has
 * one.
 */
function leads(
  table: CatalogTable,
  column: string,
  tenant: string | undefined,
  method: "btree" | "gin",
): boolean {
  return table.indexes.some((index) => {
    if ((index.method ?? "btree") !== method || index.partial) {
      return false;
    }

    if (method === "gin") {
      return index.columns.includes(column);
    }

    const [first, second] = index.columns;

    return first === column || (first === tenant && second === column);
  });
}

function check(context: DoctorContext): FindingInput[] {
  if (
    context.config.gen.entityPages === undefined ||
    context.snapshot.extras.tables.length === 0
  ) {
    return [];
  }

  const tables = catalogOf(context).tables;

  return resolveEntityPages(context.config).flatMap((entry) =>
    entityPageIndexes(entry).flatMap((index): FindingInput[] => {
      const table = tables.find(
        (each) =>
          each.schema === index.table.schema && each.name === index.table.name,
      );

      if (table === undefined) {
        return [];
      }

      if (leads(table, index.column, index.table.tenant, index.method)) {
        return [];
      }

      const what =
        index.kind === "search"
          ? `search on ${index.serves}`
          : `${index.kind} ${index.serves}`;

      return [
        {
          message: `${entry.page.entity} lists with ${what}, but ${qualified(table)} has no ${index.method} index that starts with ${index.column}${index.table.tenant === undefined ? "" : ` after ${index.table.tenant}`}. Run \`better-supabase gen\` to write the index, or add it in the schema file.`,
          target: `${qualified(table)}:${index.kind}:${index.serves}`,
          object: tableObject(table),
        },
      ];
    }),
  );
}

export const ENTITY_PAGE_INDEX_RULES: readonly Rule[] = [
  {
    code: "BS636",
    severity: "warning",
    title: "An entity page's list has no index for a sort, facet or search",
    description:
      "A page declared in `gen.entityPages` lists its entity by the sorts, facets and searched columns its block manifest declares. Each one that is a column of the entity's table needs a btree index that starts with the column (after the tenant column), or a GIN trigram index for a searched column. Without it the page sorts or groups the tenant's rows on every request. `gen` writes the indexes in a migration (`_better_supabase_entity_page_indexes.sql`); run it, or add the index to the schema file.",
    check,
  },
];
