import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** The subject types a kind of link accepts at each end. */
export interface RelationKindTypes {
  /** Subject types the link may start from; any type when left out. */
  readonly source?: readonly string[];
  /** Subject types the link may point at; any type when left out. */
  readonly target?: readonly string[];
}

/** One entry of `blocks.relations.options.kinds`. */
export interface RelationKindOptions {
  /** The name of the link read from the target's side, such as `blocked_by`. */
  readonly inverse?: string;
  /** Refuse a link that would close a cycle of this kind. */
  readonly acyclic?: boolean;
  /** `one`: a source has at most one target of this kind. */
  readonly cardinality?: "one" | "many";
  /** The link reads the same from both ends; it is stored once. */
  readonly symmetric?: boolean;
  /** The subject types `link` accepts, in the stored direction. */
  readonly types?: RelationKindTypes;
}

/** `blocks.relations.options`. */
export type RelationsSqlOptions = {
  readonly kinds?: Readonly<Record<string, RelationKindOptions>>;
  readonly extraColumns?: ExtraColumns;
};

export const relationsSqlOptions: BlockOptionsSchema<RelationsSqlOptions> =
  blockOptions<RelationsSqlOptions>({
    kinds: option.unknown<Readonly<Record<string, RelationKindOptions>>>(),
    extraColumns: option.extraColumns(),
  });
