import type { BlockTransport } from "../../src/core/block-transport.ts";

/** A fake transport for the `fields` tests: canned results by function, and the calls it saw. */
export function fieldsTransport(
  results: Readonly<Record<string, (args: Record<string, unknown>) => unknown>>,
): BlockTransport & {
  readonly calls: [string, Record<string, unknown>][];
} {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const result = results[fn];
      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      return Promise.resolve(result({ ...args }));
    },
  };
}
