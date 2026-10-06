import type { FindManyArgs } from "../ir/args.ts";
import type { AnyModels } from "../schema/types.ts";

/** `db.$search(table, args)`: the `k` rows nearest to `vector`. */
export type SearchArgs<M extends AnyModels, T extends keyof M> = Pick<
  FindManyArgs<M, T>,
  "select" | "include" | "where" | "signal"
> & {
  /** The query embedding, as numbers or pgvector text (`'[0.1,0.2]'`). */
  readonly vector: readonly number[] | string;
  /** Rows to return. Defaults to 10. */
  readonly k?: number;
  /**
   * Values for the entry's `prefilter` columns, applied before ranking: a
   * value or a list (`null` matches a null column).
   */
  readonly filter?: Readonly<Record<string, unknown>>;
  /** The text query a `hybrid` entry ranks with full-text search. */
  readonly text?: string;
  /** Adds `$score` to each row: the entry's similarity, fused and boosted. */
  readonly score?: boolean;
};

/** What `db.$search` adds to each row with `score: true`. */
export type SearchScore<A> = A extends { readonly score: true }
  ? { readonly $score: number }
  : unknown;

export interface SearchInput {
  readonly vector: readonly number[] | string;
  readonly k?: number;
  readonly filter?: Readonly<Record<string, unknown>>;
  readonly text?: string;
  readonly score?: boolean;
  readonly select?: readonly string[];
  readonly include?: Readonly<Record<string, unknown>>;
  readonly where?: unknown;
  readonly signal?: AbortSignal;
}

/** pgvector's text form, or `undefined` for anything that isn't a finite vector. */
export function vectorLiteral(
  vector: readonly number[] | string,
): string | undefined {
  if (typeof vector === "string") {
    return /^\[[^\]]+\]$/.test(vector.trim()) ? vector.trim() : undefined;
  }
  if (vector.length === 0 || !vector.every(Number.isFinite)) return undefined;
  return `[${vector.join(",")}]`;
}
