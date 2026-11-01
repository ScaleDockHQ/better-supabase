import type { BlockSqlContext } from "./context.ts";

/**
 * One declared link from an entity of this module to an entity of another
 * block.
 *
 * - `reference`: the source row holds a typed pair (`origin_type`, `origin_id`)
 *   or a foreign key to the target when it is installed.
 * - `relation`: the link is a contributed `relations` kind.
 * - `conversion`: an action creates the target from the source and records a
 *   `created_from` relation (and its inverse `converted_to`).
 */
export interface BlockSqlLink {
  /** Unique within the module. */
  readonly key: string;
  readonly kind: "conversion" | "reference" | "relation";
  /** The entity of this module the link starts at. */
  readonly source: string;
  /** The block and entity the link points at. */
  readonly target: { readonly block: string; readonly entity: string };
  /**
   * The function or action that follows the link: a conversion's action
   * (`quote_from_deal`), or the relation kind of a `relation` link.
   */
  readonly via?: string;
}

/** Declares a link in one line. */
export const link = (
  key: string,
  kind: BlockSqlLink["kind"],
  source: string,
  block: string,
  entity: string,
  via?: string,
): BlockSqlLink => ({
  key,
  kind,
  source,
  target: { block, entity },
  ...(via === undefined ? {} : { via }),
});

/** The relation kind a conversion records, and its inverse. */
export const CONVERSION_KIND = "created_from";

/** What `createdFromLink` needs: the new row and the row it came from. */
export interface CreatedFrom {
  readonly tenant: string;
  readonly sourceType: string;
  readonly sourceId: string;
  readonly originType: string;
  readonly originId: string;
}

/**
 * SQL that records `source` as created from `origin` when the relations module
 * is installed, so lineage reads find the chain. Without relations the source
 * row keeps its `origin_type` and `origin_id` columns and the SQL is empty.
 * Every conversion goes through this one helper.
 */
export function createdFromLink(
  ctx: BlockSqlContext,
  link: CreatedFrom,
): string {
  if (!ctx.installed("relations")) {
    return "";
  }

  const r = ctx.of("relations");
  const col = (name: string): string => r.col("relations", name);

  return `insert into ${r.table("relations")} (${col("tenant")}, ${col("kind")}, ${col("sourceType")}, ${col("sourceId")}, ${col("targetType")}, ${col("targetId")}, ${col("createdBy")})
    select ${link.tenant}, '${CONVERSION_KIND}', ${link.sourceType}, ${link.sourceId}, ${link.originType}, ${link.originId}, auth.uid()
    where not exists (
      select 1 from ${r.table("relations")} x
      where x.${col("kind")} = '${CONVERSION_KIND}' and x.${col("sourceType")} = ${link.sourceType} and x.${col("sourceId")} = ${link.sourceId}
    );`;
}

/** Whether a link needs the `relations` block to be recorded. */
export const linkNeedsRelations = (link: BlockSqlLink): boolean =>
  link.kind === "conversion" || link.kind === "relation";
