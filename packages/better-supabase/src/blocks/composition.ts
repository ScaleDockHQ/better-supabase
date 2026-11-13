/**
 * How a declared link points at its target (ADR 0196): `reference` is a typed
 * pair or a foreign key, `relation` a contributed `relations` kind and
 * `conversion` an action that creates the target and records `created_from`.
 */
export type BlockLinkKind = "conversion" | "reference" | "relation";

/**
 * One link from an entity of the block to an entity of another block. The SQL
 * module's `NAMES.links` holds the same link, and a test keeps the two equal,
 * so the catalog and the page generator read the manifest.
 */
export interface BlockLink {
  /** Unique within the block. */
  readonly key: string;
  readonly kind: BlockLinkKind;
  /** The entity of this block the link starts at. */
  readonly source: string;
  /** The block and entity the link points at. */
  readonly target: { readonly block: string; readonly entity: string };
  /**
   * The action or function that follows the link: a conversion's action, or the
   * relation kind of a `relation` link.
   */
  readonly via?: string;
}

/**
 * The row-level concerns a block's tables take part in beyond the default.
 * Every block table already gets row audit and event triggers (ADR 0196), so
 * those two are not listed.
 *
 * - `history`: an entity keeps the changes of named columns (`field-history`).
 * - `lifecycle`: a table declares its owner columns for export and purge
 *   (`data-lifecycle`).
 * - `realtime`: an entity's table is tracked for Realtime.
 * - `search`: an entity registers its title and body for search.
 */
export type BlockConcern = "history" | "lifecycle" | "realtime" | "search";

/** Every `BlockConcern`, in the order a manifest lists them. */
export const BLOCK_CONCERNS: readonly BlockConcern[] = [
  "history",
  "lifecycle",
  "realtime",
  "search",
];

/** Declares a link in one line. */
export const blockLink = (
  key: string,
  kind: BlockLinkKind,
  source: string,
  block: string,
  entity: string,
  via?: string,
): BlockLink => ({
  key,
  kind,
  source,
  target: { block, entity },
  ...(via === undefined ? {} : { via }),
});
