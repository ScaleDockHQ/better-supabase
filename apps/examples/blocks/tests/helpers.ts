import type { BlockTransport } from "better-supabase/blocks";

type Args = Parameters<BlockTransport["call"]>[2];

type Canned = (args: Args) => object | null;

/** A transport with canned results by function name, and the calls it saw. */
export function cannedTransport(
  results: Readonly<Record<string, Canned>>,
): BlockTransport & { readonly calls: [string, Args][] } {
  const calls: [string, Args][] = [];

  return {
    calls,
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const result = results[fn];

      return result
        ? Promise.resolve(result({ ...args }))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };
}
