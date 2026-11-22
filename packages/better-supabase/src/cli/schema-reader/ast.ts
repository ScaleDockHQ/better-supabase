/** A parse tree node: one key that names the node type, its body as value. */
export type Obj = Readonly<Record<string, unknown>>;

export function isObj(value: unknown): value is Obj {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function obj(value: unknown): Obj {
  return isObj(value) ? value : {};
}

export function list(value: unknown): readonly unknown[] {
  return Array.isArray(value) ? value : [];
}

export function str(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/** `{ CreateStmt: {...} }` as `["CreateStmt", {...}]`. */
export function unwrap(node: unknown): readonly [string, Obj] | undefined {
  if (!isObj(node)) {
    return undefined;
  }

  const [entry] = Object.entries(node);

  return entry === undefined ? undefined : [entry[0], obj(entry[1])];
}

/** The body of `node` when it is a `type` node. */
export function bodyOf(node: unknown, type: string): Obj | undefined {
  const unwrapped = unwrap(node);

  return unwrapped?.[0] === type ? unwrapped[1] : undefined;
}

/** The strings of a list of `{ String: { sval } }` nodes. */
export function strings(value: unknown): readonly string[] {
  return list(value).flatMap((item) => {
    const text = str(bodyOf(item, "String")?.["sval"]);

    return text === undefined ? [] : [text];
  });
}

/** Every column a tree names, in source order, without repeats. */
export function columnRefs(node: unknown): readonly string[] {
  const found: string[] = [];

  const walk = (value: unknown): void => {
    if (Array.isArray(value)) {
      for (const item of value) {
        walk(item);
      }

      return;
    }

    if (!isObj(value)) {
      return;
    }

    for (const [key, child] of Object.entries(value)) {
      if (key === "ColumnRef") {
        const last = strings(obj(child)["fields"]).at(-1);

        if (last !== undefined && !found.includes(last)) {
          found.push(last);
        }
      } else {
        walk(child);
      }
    }
  };

  walk(node);

  return found;
}
