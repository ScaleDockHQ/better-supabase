import type { FindManyArgs } from '../ir/args.ts';
import type { AnyModels } from '../schema/types.ts';

/** `db.$search(table, args)`: the `k` rows nearest to `vector`. */
export type SearchArgs<M extends AnyModels, T extends keyof M> = Pick<
  FindManyArgs<M, T>,
  'select' | 'include' | 'where' | 'signal'
> & {
  /** The query embedding, as numbers or pgvector text (`'[0.1,0.2]'`). */
  readonly vector: readonly number[] | string;
  /** Rows to return. Defaults to 10. */
  readonly k?: number;
};

export interface SearchInput {
  readonly vector: readonly number[] | string;
  readonly k?: number;
  readonly select?: readonly string[];
  readonly include?: Readonly<Record<string, unknown>>;
  readonly where?: unknown;
  readonly signal?: AbortSignal;
}

/** pgvector's text form, or `undefined` for anything that isn't a finite vector. */
export function vectorLiteral(
  vector: readonly number[] | string,
): string | undefined {
  if (typeof vector === 'string') {
    return /^\[[^\]]+\]$/.test(vector.trim()) ? vector.trim() : undefined;
  }
  if (vector.length === 0 || !vector.every(Number.isFinite)) return undefined;
  return `[${vector.join(',')}]`;
}
