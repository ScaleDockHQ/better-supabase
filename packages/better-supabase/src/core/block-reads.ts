import type { FunctionSpec } from "./spec.ts";

declare const readTypes: unique symbol;

/**
 * One composed read a block ships: a `stable` SQL function that returns
 * `jsonb`. `better-supabase gen` writes these into `blocks.generated.ts`
 * (`reads`) with the function's name under the configured naming.
 */
export interface BlockRead<A extends object = object, R = unknown> {
  readonly fn: string;
  /** Argument key to the SQL function's parameter name. */
  readonly params: Readonly<Record<string, string>>;
  /** Type-only: the arguments and the result. */
  readonly [readTypes]?: (args: A) => R;
}

/** The reads of the installed blocks: instance, then read name. */
export type BlockReadMap = Readonly<
  Record<string, Readonly<Record<string, BlockRead<never>>>>
>;

type ArgsOf<T> = T extends { readonly [readTypes]?: (args: infer A) => unknown }
  ? A
  : never;

type ResultOf<T> = T extends { readonly [readTypes]?: (args: never) => infer R }
  ? R
  : never;

/** What `s.blocks` offers a read set: one call builder per block read. */
export type BlockReadSpecs<B extends BlockReadMap> = {
  readonly [I in keyof B]: {
    readonly [R in keyof B[I]]: (
      args: ArgsOf<B[I][R]>,
    ) => FunctionSpec<string, ResultOf<B[I][R]>>;
  };
};

/** Declares one read for `blocks.generated.ts`. */
export function blockRead<A extends object, R>(
  fn: string,
  params: Readonly<Record<string, string>>,
): BlockRead<A, R> {
  return { fn, params };
}

/** The builders behind `s.blocks`: each maps its arguments to the function's. */
export function createBlockReadSpecs<B extends BlockReadMap>(
  reads: B,
): BlockReadSpecs<B> {
  const out: Record<string, Record<string, unknown>> = {};

  for (const [instance, entries] of Object.entries(reads)) {
    out[instance] = Object.fromEntries(
      Object.entries(entries).map(([name, read]) => [
        name,
        (args: Readonly<Record<string, unknown>> = {}): FunctionSpec => ({
          v: 1,
          kind: "function",
          name: read.fn,
          args: Object.fromEntries(
            Object.entries(args).map(([key, value]) => [
              read.params[key] ?? key,
              value,
            ]),
          ),
        }),
      ]),
    );
  }

  // SAFETY: every entry above is a builder for the read it is keyed by.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the builders are built from the same map B types.
  return out as unknown as BlockReadSpecs<B>;
}
