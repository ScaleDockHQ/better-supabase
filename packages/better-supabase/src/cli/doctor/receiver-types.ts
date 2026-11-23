import type { Node } from "oxc-parser";

import { resolve } from "node:path";

import type { ProjectSymbols } from "../typescript-symbols/index.ts";

import { receiverOffset } from "./tree.ts";

/**
 * Types that name a plain collection or value. A receiver named `db` or
 * `userService` that has one of these types is not a database client.
 */
const NOT_A_CLIENT =
  /^(?:readonly )?(?:Map|Set|WeakMap|WeakSet|Array|ReadonlyArray|ReadonlyMap|ReadonlySet|Record|Headers|URLSearchParams|FormData|Storage|string|number|boolean|bigint|Date)\b|\[\]$/;

/**
 * Whether TypeScript proves the identifier at `offset` in `path` is not a
 * database client: `true` for a collection or primitive, `false` for any other
 * type, `undefined` when the tier is off or the checker cannot resolve it.
 */
export function provablyNotClient(
  symbols: ProjectSymbols | undefined,
  path: string,
  offset: number,
): boolean | undefined {
  if (symbols === undefined || "skipped" in symbols) {
    return undefined;
  }

  const type = symbols.tier.typeOf(resolve(symbols.root, path), offset);

  return type === undefined ? undefined : NOT_A_CLIENT.test(type);
}

/**
 * Whether TypeScript proves the receiver of the `call` node is a collection or
 * a primitive, so a call that only matched by its method name is not a database
 * call. `false` when the tier is off, the call has no named receiver, or the
 * checker cannot type it.
 */
export function receiverIsNotClient(
  symbols: ProjectSymbols | undefined,
  path: string,
  call: Node,
): boolean {
  const at = receiverOffset(call);

  return at !== undefined && provablyNotClient(symbols, path, at) === true;
}

/** Rules that match a receiver by its name before the tier checks its type. */
export const RECEIVER_RULES: ReadonlySet<string> = new Set([
  "BS210",
  "BS219",
  "BS227",
  "BS351",
  "BS609",
  "BS634",
  "BS635",
]);
