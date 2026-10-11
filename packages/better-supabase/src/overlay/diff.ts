import type { PathSegment } from "./path.ts";
import type {
  Overlay,
  Overlay10,
  Overlay11,
  Overlay12,
  OverlayAction,
  OverlayInfo,
  OverlayVersion,
} from "./types.ts";

import { isObject } from "./apply.ts";
import { formatPath } from "./path.ts";

export interface OverlayFromDiffOptions<V extends OverlayVersion> {
  /** The Overlay version to write. Default `1.1.0`. */
  readonly version?: V;
  /** Default `{ title: "better-supabase changes", version: "1.0.0" }`. */
  readonly info?: OverlayInfo;
  readonly extends?: string;
}

type OverlayOf<V extends OverlayVersion> = V extends "1.0.0"
  ? Overlay10
  : V extends "1.2.0"
    ? Overlay12
    : Overlay11;

type Kind = "object" | "array" | "primitive";
const kindOf = (value: unknown): Kind =>
  Array.isArray(value) ? "array" : isObject(value) ? "object" : "primitive";

function equal(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) && Array.isArray(b))
    return a.length === b.length && a.every((item, i) => equal(item, b[i]));
  if (isObject(a) && isObject(b)) {
    const keys = Object.keys(a);
    return (
      keys.length === Object.keys(b).length &&
      keys.every((key) => Object.hasOwn(b, key) && equal(a[key], b[key]))
    );
  }
  return false;
}

interface Context {
  readonly replacePrimitives: boolean;
  readonly actions: OverlayAction[];
}

/**
 * Appends the actions that turn the array `a` into `b`, or returns `false`
 * when the change needs the array replaced as a whole.
 */
function diffArray(
  path: readonly PathSegment[],
  a: readonly unknown[],
  b: readonly unknown[],
  ctx: Context,
): boolean {
  if (b.length >= a.length && a.every((item, i) => equal(item, b[i]))) {
    if (b.length > a.length)
      ctx.actions.push({ target: formatPath(path), update: b.slice(a.length) });
    return true;
  }
  if (a.length !== b.length) return false;
  const pending: OverlayAction[] = [];
  for (const [i, item] of a.entries()) {
    const next = b[i];
    if (equal(item, next)) continue;
    if (!isObject(item) || !isObject(next)) return false;
    diffObject([...path, i], item, next, { ...ctx, actions: pending });
  }
  ctx.actions.push(...pending);
  return true;
}

function diffObject(
  path: readonly PathSegment[],
  a: Readonly<Record<string, unknown>>,
  b: Readonly<Record<string, unknown>>,
  ctx: Context,
): void {
  const removals: OverlayAction[] = [];
  const added: Record<string, unknown> = {};
  const nested: OverlayAction[] = [];
  const replace = (key: string, value: unknown): void => {
    removals.push({ target: formatPath([...path, key]), remove: true });
    added[key] = value;
  };
  for (const key of Object.keys(a))
    if (!Object.hasOwn(b, key))
      removals.push({ target: formatPath([...path, key]), remove: true });
  for (const [key, next] of Object.entries(b)) {
    if (!Object.hasOwn(a, key)) {
      added[key] = next;
      continue;
    }
    const current = a[key];
    if (equal(current, next)) continue;
    const kind = kindOf(current);
    if (kind !== kindOf(next)) replace(key, next);
    else if (isObject(current) && isObject(next))
      diffObject([...path, key], current, next, { ...ctx, actions: nested });
    else if (Array.isArray(current) && Array.isArray(next)) {
      if (
        !diffArray([...path, key], current, next, { ...ctx, actions: nested })
      )
        replace(key, next);
    } else if (ctx.replacePrimitives)
      nested.push({ target: formatPath([...path, key]), update: next });
    else replace(key, next);
  }
  ctx.actions.push(...removals);
  if (Object.keys(added).length > 0)
    ctx.actions.push({ target: formatPath(path), update: added });
  ctx.actions.push(...nested);
}

/**
 * Writes the Overlay that turns `base` into `enriched`, so other tools can
 * reproduce what hooks and transforms changed. Targets use stable keys
 * (`$.paths['/customers'].get`); array indexes appear only inside arrays of
 * the same length.
 *
 * A deleted key becomes a `remove` action; added keys become one `update` on
 * their parent; a changed primitive becomes an `update` on it (1.1 and
 * later) or a `remove` and re-add (1.0). An array that only grew gets its new
 * items appended; any other array change replaces the array. Applying the
 * result to `base` gives a document equal to `enriched`, though replaced
 * keys move to the end of their object.
 *
 * Throws a `TypeError` when the roots are not both objects, or when the two
 * documents are equal (an overlay needs at least one action).
 */
export function overlayFromDiff<V extends OverlayVersion = "1.1.0">(
  base: unknown,
  enriched: unknown,
  options: OverlayFromDiffOptions<V> = {},
): OverlayOf<V> {
  if (!isObject(base) || !isObject(enriched))
    throw new TypeError("overlayFromDiff: both documents must be objects");
  const version: OverlayVersion = options.version ?? "1.1.0";
  const actions: OverlayAction[] = [];
  diffObject([], base, enriched, {
    replacePrimitives: version !== "1.0.0",
    actions,
  });
  if (actions.length === 0)
    throw new TypeError(
      "overlayFromDiff: the documents are equal, so there is nothing to write",
    );
  const overlay: Overlay = {
    overlay: version,
    info: options.info ?? {
      title: "better-supabase changes",
      version: "1.0.0",
    },
    ...(options.extends === undefined ? {} : { extends: options.extends }),
    actions,
  };
  // SAFETY: `overlay` carries the requested version, which is what OverlayOf<V> selects on.
  return overlay as OverlayOf<V>;
}
