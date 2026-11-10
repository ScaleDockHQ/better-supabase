import { sha256Hex } from "../sha256.ts";
import { stableText } from "./render-key.ts";

/** The two inputs a module render reads: the layout and the installed names. */
export type ReadRoot = "layout" | "installed";

/**
 * One thing a render read, with what it saw. `value` is a primitive at `path`,
 * `type` the kind of object there, `keys` the own keys of the object, `has`
 * whether the key exists (`in` and absent reads), and `whole` an object the
 * render took by reference and may have read without the proxy (a map or a
 * set). `member` is whether an array holds the string that ends the path (the
 * array's own path is everything before it), so a render that asks `includes`
 * depends on that one answer and not on every element.
 */
export interface Read {
  readonly root: ReadRoot;
  readonly path: readonly string[];
  readonly kind: "value" | "type" | "keys" | "has" | "whole" | "member";
  readonly seen: string;
}

const isPlain = (value: object): boolean => {
  const proto: unknown = Object.getPrototypeOf(value);

  return proto === Object.prototype || proto === null;
};

const trackable = (value: unknown): value is object =>
  typeof value === "object" &&
  value !== null &&
  (Array.isArray(value) || isPlain(value));

/** Long texts are kept as their hash, so a read set stays small. */
const digest = (text: string): string =>
  text.length <= 64 ? text : `h:${sha256Hex(text)}`;

const kindOf = (value: unknown): string => {
  if (value === null) {
    return "null";
  }

  if (Array.isArray(value)) {
    return "array";
  }

  return typeof value === "object" && isPlain(value) ? "object" : typeof value;
};

/** `value` at `path` below `root`, or `undefined` when a step is missing. */
function resolvePath(root: unknown, path: readonly string[]): unknown {
  let current = root;

  for (const key of path) {
    if (
      typeof current !== "object" ||
      current === null ||
      !Object.hasOwn(current, key)
    ) {
      return undefined;
    }

    // SAFETY: `current` is an object with its own `key`, checked above.
    current = (current as Record<string, unknown>)[key];
  }

  return current;
}

/** What `read` would see in `layout` and `installed` now. */
function seenNow(
  read: Read,
  roots: Readonly<Record<ReadRoot, unknown>>,
): string | undefined {
  const root = roots[read.root];

  if (read.kind === "has") {
    const parent = resolvePath(root, read.path.slice(0, -1));
    const key = read.path.at(-1) ?? "";

    return typeof parent === "object" &&
      parent !== null &&
      Object.hasOwn(parent, key)
      ? "1"
      : "0";
  }

  if (read.kind === "member") {
    const list = resolvePath(root, read.path.slice(0, -1));

    return Array.isArray(list) && list.includes(read.path.at(-1)) ? "1" : "0";
  }

  const value = resolvePath(root, read.path);

  switch (read.kind) {
    case "type": {
      return kindOf(value);
    }

    case "keys": {
      return typeof value === "object" && value !== null
        ? digest(JSON.stringify(Object.keys(value)))
        : "-";
    }

    case "value":
    case "whole": {
      const text = stableText(value);

      return text === undefined ? undefined : digest(text);
    }

    default: {
      const never: never = read.kind;

      return never;
    }
  }
}

/** Whether every read in `reads` sees today what it saw when it was recorded. */
export function readsHold(
  reads: readonly Read[],
  roots: Readonly<Record<ReadRoot, unknown>>,
): boolean {
  return reads.every((read) => seenNow(read, roots) === read.seen);
}

/** Records what a render reads through the values `wrap` returns. */
export interface ReadTracker {
  /** The reads so far, one per root, path and kind. */
  readonly reads: () => readonly Read[];
  /**
   * The render read something no read set can describe (a function) or wrote to
   * its input, so its result must not be cached.
   */
  readonly uncacheable: () => boolean;
  /** `value` behind a proxy that records every read of it. */
  readonly wrap: <T>(root: ReadRoot, value: T) => T;
}

/**
 * A tracker for one render. The proxies forward to the real values, hold a
 * stand-in target (so a frozen input never breaks a proxy invariant) and hand
 * out proxies for nested plain objects and arrays. A map, set or class instance
 * is returned as it is and recorded as a whole.
 */
export function createReadTracker(): ReadTracker {
  const reads = new Map<string, Read>();
  let blocked = false;

  const record = (
    root: ReadRoot,
    path: readonly string[],
    kind: Read["kind"],
    seen: string | undefined,
  ): void => {
    if (seen === undefined) {
      blocked = true;

      return;
    }

    reads.set(`${root}\u0000${kind}\u0000${path.join("\u0000")}`, {
      root,
      path,
      kind,
      seen,
    });
  };

  const view = (
    real: object,
    root: ReadRoot,
    path: readonly string[],
  ): object =>
    new Proxy(Array.isArray(real) ? [] : {}, {
      get(_target, key) {
        if (typeof key === "symbol") {
          // SAFETY: a symbol key reads an inherited member such as `Symbol.iterator`.
          return (real as Record<symbol, unknown>)[key];
        }

        const own = Object.hasOwn(real, key);

        // `includes` of a string records the one answer, not every element.
        if (key === "includes" && Array.isArray(real)) {
          return (search: unknown, from?: number): boolean => {
            const found = real.includes(search, from);

            if (typeof search === "string" && from === undefined) {
              record(root, [...path, search], "member", found ? "1" : "0");
            } else {
              for (const [index, item] of real.entries()) {
                record(
                  root,
                  [...path, String(index)],
                  "value",
                  digest(stableText(item) ?? ""),
                );
              }
            }

            return found;
          };
        }

        // Inherited members (`indexOf`, `hasOwnProperty`) read no data.
        if (!own && key in real) {
          // SAFETY: `key` is a string member of `real`, found by `in`.
          return (real as Record<string, unknown>)[key];
        }

        const child = [...path, key];

        if (!own) {
          record(root, child, "has", "0");

          return;
        }

        // SAFETY: `real` has its own `key`, checked above.
        const value = (real as Record<string, unknown>)[key];

        if (trackable(value)) {
          record(root, child, "type", kindOf(value));

          return view(value, root, child);
        }

        if (typeof value === "function" || typeof value === "symbol") {
          blocked = true;

          return value;
        }

        const text = stableText(value);
        const object = typeof value === "object" && value !== null;
        record(
          root,
          child,
          object ? "whole" : "value",
          text === undefined ? undefined : digest(text),
        );

        return value;
      },
      has(_target, key) {
        const present = Reflect.has(real, key);

        if (typeof key === "string") {
          record(
            root,
            [...path, key],
            "has",
            Object.hasOwn(real, key) ? "1" : "0",
          );
        }

        return present;
      },
      ownKeys() {
        const keys = Reflect.ownKeys(real);

        record(
          root,
          path,
          "keys",
          digest(JSON.stringify(keys.filter((key) => typeof key === "string"))),
        );

        return keys;
      },
      getOwnPropertyDescriptor(_target, key) {
        const descriptor = Reflect.getOwnPropertyDescriptor(real, key);

        if (descriptor === undefined) {
          return;
        }

        if (Array.isArray(real) && key === "length") {
          return {
            value: real.length,
            writable: true,
            enumerable: false,
            configurable: false,
          };
        }

        return {
          value: undefined,
          writable: true,
          enumerable: descriptor.enumerable ?? false,
          configurable: true,
        };
      },
      getPrototypeOf() {
        return Reflect.getPrototypeOf(real);
      },
      set(_target, key, value) {
        blocked = true;

        return Reflect.set(real, key, value);
      },
      defineProperty(_target, key, descriptor) {
        blocked = true;

        return Reflect.defineProperty(real, key, descriptor);
      },
      deleteProperty(_target, key) {
        blocked = true;

        return Reflect.deleteProperty(real, key);
      },
    });

  return {
    reads: () => [...reads.values()],
    uncacheable: () => blocked,
    wrap<T>(root: ReadRoot, value: T): T {
      if (!trackable(value)) {
        return value;
      }

      record(root, [], "type", kindOf(value));

      // SAFETY: the proxy forwards every operation to `value`, so it has the type of `value`.
      return view(value, root, []) as T;
    },
  };
}
