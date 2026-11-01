import type { BlockReadMap } from "../core/block-reads.ts";
import type { BetterSupabase } from "../core/define.ts";
import type {
  ReadSet,
  ReadSetParamTypes,
  ReadSetParams,
} from "../core/read-set.ts";
import type { ReadSetEntry } from "../core/spec.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { defineReadSet } from "../core/read-set.ts";

/** One block read a composite's read set calls. */
export interface CompositeReadEntry {
  /** The block instance, as `blocks.generated.ts` lists it under `reads`. */
  readonly block: string;
  /** The read's name on that block. */
  readonly read: string;
  /** The read's arguments, each the name of a read set parameter. */
  readonly args?: Readonly<Record<string, string>>;
}

/**
 * A named read set a composite ships: the block reads one of its pages shows,
 * as one `rs_<name>` call. It is data, so the catalog and Create can list it;
 * `defineCompositeReadSet` turns it into a real read set for the app's schema.
 */
export interface CompositeReadSet<
  N extends string = string,
  P extends ReadSetParamTypes = ReadSetParamTypes,
> {
  readonly name: N;
  readonly params: P;
  /** The entries by result key. */
  readonly reads: Readonly<Record<string, CompositeReadEntry>>;
}

/** Declares a composite's read set. */
export function compositeReadSet<
  const N extends string,
  const P extends ReadSetParamTypes,
>(
  name: N,
  params: P,
  reads: Readonly<Record<string, CompositeReadEntry>>,
): CompositeReadSet<N, P> {
  return { name, params, reads };
}

/**
 * Builds the read set a composite declares over the app's schema and the block
 * reads `better-supabase gen` wrote (`reads` in `blocks.generated.ts`). Throws
 * when an entry names a block or a read the app doesn't install.
 */
export function defineCompositeReadSet<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  const N extends string,
  const P extends ReadSetParamTypes,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  set: CompositeReadSet<N, P>,
  reads: BlockReadMap,
): ReadSet<N, P> {
  for (const [key, entry] of Object.entries(set.reads)) {
    if (reads[entry.block]?.[entry.read] === undefined) {
      throw new TypeError(
        `better-supabase: read set "${set.name}" entry "${key}" needs the ${entry.block}.${entry.read} read, which the installed blocks don't ship`,
      );
    }
  }

  return defineReadSet(
    betterSupabase,
    set.name,
    { params: set.params, blocks: reads },
    (specs, params) =>
      Object.fromEntries(
        Object.entries(set.reads).map(([key, entry]) => {
          const args = Object.fromEntries(
            Object.entries(entry.args ?? {}).map(([arg, param]) => [
              arg,
              // SAFETY: the placeholders are keyed by the declared parameter names.
              (params as ReadSetParams<ReadSetParamTypes>)[param],
            ]),
          );

          // SAFETY: the read was checked above, and its builder takes the
          // arguments by name.
          const build = specs.blocks[entry.block]?.[entry.read] as (
            args: Record<string, unknown>,
          ) => ReadSetEntry;

          return [key, build(args)];
        }),
      ),
  );
}
