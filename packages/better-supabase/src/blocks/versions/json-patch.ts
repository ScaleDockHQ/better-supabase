/** A JSON value, as a version's content holds it. */
export type JsonValue =
  | null
  | boolean
  | number
  | string
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

/** One RFC 6902 JSON Patch operation. Paths are RFC 6901 JSON Pointers. */
export type JsonPatchOperation =
  | { readonly op: "add"; readonly path: string; readonly value: JsonValue }
  | { readonly op: "remove"; readonly path: string }
  | { readonly op: "replace"; readonly path: string; readonly value: JsonValue }
  | { readonly op: "move"; readonly from: string; readonly path: string }
  | { readonly op: "copy"; readonly from: string; readonly path: string }
  | { readonly op: "test"; readonly path: string; readonly value: JsonValue };

/** Thrown by `applyPatch` for an operation RFC 6902 calls an error. */
export class JsonPatchError extends Error {
  override readonly name = "JsonPatchError";
  /** The index of the failing operation in the patch. */
  readonly index: number;

  constructor(message: string, index: number) {
    super(message);
    this.index = index;
  }
}

type Mutable = null | boolean | number | string | Mutable[] | Container;
interface Container {
  [key: string]: Mutable;
}

const isObject = (value: unknown): value is Container =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const escape = (token: string): string =>
  token.replaceAll("~", "~0").replaceAll("/", "~1");

/** The reference tokens of an RFC 6901 pointer. */
function tokensOf(pointer: string, index: number): string[] {
  if (pointer === "") {
    return [];
  }
  if (!pointer.startsWith("/")) {
    throw new JsonPatchError(`"${pointer}" is not a JSON Pointer`, index);
  }
  return pointer
    .slice(1)
    .split("/")
    .map((token) => {
      if (/~[^01]|~$/.test(token)) {
        throw new JsonPatchError(`"${pointer}" has an invalid escape`, index);
      }
      return token.replaceAll("~1", "/").replaceAll("~0", "~");
    });
}

const ARRAY_INDEX = /^(0|[1-9][0-9]*)$/;

function arrayIndex(
  array: readonly unknown[],
  token: string,
  index: number,
  adding: boolean,
): number {
  if (adding && token === "-") {
    return array.length;
  }
  if (!ARRAY_INDEX.test(token)) {
    throw new JsonPatchError(`"${token}" is not an array index`, index);
  }
  const position = Number(token);
  if (position > array.length || (!adding && position === array.length)) {
    throw new JsonPatchError(`index ${token} is out of bounds`, index);
  }
  return position;
}

/** Deep equality of two JSON values; object key order doesn't matter. */
export function jsonEqual(a: JsonValue, b: JsonValue): boolean {
  if (a === b) {
    return true;
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) {
      return false;
    }
    const left: readonly JsonValue[] = a;
    const right: readonly JsonValue[] = b;
    return left.every((item, i) => jsonEqual(item, right[i] ?? null));
  }
  if (!isObject(a) || !isObject(b)) {
    return false;
  }
  const keys = Object.keys(a);
  if (keys.length !== Object.keys(b).length) {
    return false;
  }
  return keys.every(
    (key) => Object.hasOwn(b, key) && jsonEqual(a[key] ?? null, b[key] ?? null),
  );
}

function clone(value: JsonValue): Mutable {
  // SAFETY: a structured clone of a JSON value is a fresh JSON value nothing else references.
  return structuredClone(value) as Mutable;
}

function get(document: Mutable, tokens: readonly string[], index: number) {
  let current: Mutable = document;
  for (const token of tokens) {
    if (Array.isArray(current)) {
      current = current[arrayIndex(current, token, index, false)] ?? null;
    } else if (isObject(current) && Object.hasOwn(current, token)) {
      current = current[token] ?? null;
    } else {
      throw new JsonPatchError(`"/${tokens.join("/")}" does not exist`, index);
    }
  }
  return current;
}

interface Root {
  value: Mutable;
}

function add(
  root: Root,
  tokens: readonly string[],
  value: Mutable,
  index: number,
): void {
  const last = tokens.at(-1);
  if (last === undefined) {
    root.value = value;
    return;
  }
  const parent = get(root.value, tokens.slice(0, -1), index);
  if (Array.isArray(parent)) {
    parent.splice(arrayIndex(parent, last, index, true), 0, value);
  } else if (isObject(parent)) {
    parent[last] = value;
  } else {
    throw new JsonPatchError("the target's parent is not a container", index);
  }
}

function remove(root: Root, tokens: readonly string[], index: number): Mutable {
  const last = tokens.at(-1);
  if (last === undefined) {
    const value = root.value;
    root.value = null;
    return value;
  }
  const parent = get(root.value, tokens.slice(0, -1), index);
  if (Array.isArray(parent)) {
    const [removed] = parent.splice(arrayIndex(parent, last, index, false), 1);
    return removed ?? null;
  }
  if (isObject(parent) && Object.hasOwn(parent, last)) {
    const value = parent[last] ?? null;
    Reflect.deleteProperty(parent, last);
    return value;
  }
  throw new JsonPatchError(`"/${tokens.join("/")}" does not exist`, index);
}

/**
 * Applies an RFC 6902 patch to a copy of `document` and returns the copy.
 * Throws a `JsonPatchError` for an operation the RFC calls an error; the
 * input is never changed.
 */
export function applyPatch(
  document: JsonValue,
  patch: readonly JsonPatchOperation[],
): JsonValue {
  const root: Root = { value: clone(document) };
  patch.forEach((operation, index) => {
    const tokens = tokensOf(operation.path, index);
    switch (operation.op) {
      case "add":
        add(root, tokens, clone(operation.value), index);
        break;
      case "remove":
        remove(root, tokens, index);
        break;
      case "replace":
        remove(root, tokens, index);
        add(root, tokens, clone(operation.value), index);
        break;
      case "move": {
        if (
          operation.path !== operation.from &&
          operation.path.startsWith(`${operation.from}/`)
        ) {
          throw new JsonPatchError(
            "a value can't be moved into one of its children",
            index,
          );
        }
        const value = remove(root, tokensOf(operation.from, index), index);
        add(root, tokens, value, index);
        break;
      }
      case "copy":
        add(
          root,
          tokens,
          clone(get(root.value, tokensOf(operation.from, index), index)),
          index,
        );
        break;
      case "test":
        if (!jsonEqual(get(root.value, tokens, index), operation.value)) {
          throw new JsonPatchError(`test failed at "${operation.path}"`, index);
        }
        break;
      default: {
        const unknown: never = operation;
        throw new JsonPatchError(
          `unknown operation ${JSON.stringify(unknown)}`,
          index,
        );
      }
    }
  });
  return root.value;
}

function diff(
  from: JsonValue,
  to: JsonValue,
  path: string,
  out: JsonPatchOperation[],
): void {
  if (jsonEqual(from, to)) {
    return;
  }
  if (Array.isArray(from) && Array.isArray(to)) {
    const left: readonly JsonValue[] = from;
    const right: readonly JsonValue[] = to;
    const shared = Math.min(left.length, right.length);
    for (let i = 0; i < shared; i += 1) {
      diff(left[i] ?? null, right[i] ?? null, `${path}/${String(i)}`, out);
    }
    for (let i = left.length - 1; i >= shared; i -= 1) {
      out.push({ op: "remove", path: `${path}/${String(i)}` });
    }
    for (let i = shared; i < right.length; i += 1) {
      out.push({
        op: "add",
        path: `${path}/${String(i)}`,
        value: right[i] ?? null,
      });
    }
    return;
  }
  if (isObject(from) && isObject(to)) {
    for (const key of Object.keys(from)) {
      if (!Object.hasOwn(to, key)) {
        out.push({ op: "remove", path: `${path}/${escape(key)}` });
      }
    }
    for (const [key, value] of Object.entries(to)) {
      const child = `${path}/${escape(key)}`;
      if (Object.hasOwn(from, key)) {
        diff(from[key] ?? null, value, child, out);
      } else {
        out.push({ op: "add", path: child, value });
      }
    }
    return;
  }
  out.push({ op: "replace", path, value: to });
}

/**
 * The RFC 6902 patch that turns `from` into `to`: `add`, `remove` and
 * `replace` operations, with array elements compared by position.
 * `applyPatch(from, createPatch(from, to))` equals `to`.
 */
export function createPatch(
  from: JsonValue,
  to: JsonValue,
): JsonPatchOperation[] {
  const out: JsonPatchOperation[] = [];
  diff(from, to, "", out);
  return out;
}
