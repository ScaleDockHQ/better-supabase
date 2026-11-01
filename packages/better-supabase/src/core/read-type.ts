/**
 * The JSON a block read returns, described once. A scalar is a name, `?` after
 * it allows `null`, an array is a one-item tuple and an object lists its keys.
 * `InferReadType` types the client method from it, and `gen` writes the same
 * type as a result type for read sets.
 *
 * `text` stands for text, uuid and the int8 amounts that SQL returns as text
 * (ADR 0037), `number` for integers and numerics that fit a double, and `json`
 * for a value the app types itself.
 */
export type ReadType =
  | ReadScalar
  | `${ReadScalar}?`
  | readonly [ReadType]
  | { readonly [key: string]: ReadType };

export type ReadScalar = "text" | "number" | "bool" | "json";

type Scalar<S extends ReadScalar> = S extends "text"
  ? string
  : S extends "number"
    ? number
    : S extends "bool"
      ? boolean
      : unknown;

/** The TypeScript type a read type describes. */
export type InferReadType<S> = S extends `${infer K extends ReadScalar}?`
  ? Scalar<K> | null
  : S extends ReadScalar
    ? Scalar<S>
    : S extends readonly [infer Item]
      ? readonly InferReadType<Item>[]
      : S extends object
        ? { readonly [K in keyof S]: InferReadType<S[K]> }
        : never;

const SCALARS: ReadonlySet<string> = new Set([
  "text",
  "number",
  "bool",
  "json",
]);

const SCALAR_TYPE: Readonly<Record<ReadScalar, string>> = {
  text: "string",
  number: "number",
  bool: "boolean",
  json: "unknown",
};

function isScalar(value: string): value is ReadScalar {
  return SCALARS.has(value);
}

function isItemType(type: ReadType): type is readonly [ReadType] {
  return Array.isArray(type);
}

const KEY = /^[A-Za-z_$][\w$]*$/;

/** The TypeScript source of a type, for generated result types. */
export function readTypeSource(type: ReadType, indent = ""): string {
  if (typeof type === "string") {
    const optional = type.endsWith("?");
    const name = optional ? type.slice(0, -1) : type;

    if (!isScalar(name)) {
      throw new TypeError(`Unknown read type "${type}"`);
    }

    const source = SCALAR_TYPE[name];

    return optional && name !== "json" ? `${source} | null` : source;
  }

  if (isItemType(type)) {
    const inner = readTypeSource(type[0], indent);

    return inner.includes(" | ") && !inner.startsWith("{")
      ? `readonly (${inner})[]`
      : `readonly ${inner}[]`;
  }

  const entries = Object.entries(type);

  if (entries.length === 0) {
    return "Record<never, never>";
  }

  const next = `${indent}  `;

  return `{\n${entries
    .map(
      ([key, each]) =>
        `${next}readonly ${KEY.test(key) ? key : JSON.stringify(key)}: ${readTypeSource(each, next)};`,
    )
    .join("\n")}\n${indent}}`;
}

function describe(value: unknown): string {
  if (value === null) {
    return "null";
  }

  return Array.isArray(value) ? "array" : typeof value;
}

function decodeAt(type: ReadType, value: unknown, path: string): unknown {
  if (typeof type === "string") {
    const nullable = type.endsWith("?");
    const name = nullable ? type.slice(0, -1) : type;

    if (value === null || value === undefined) {
      if (nullable || name === "json") {
        return null;
      }

      throw new TypeError(`${path} is ${describe(value)}, expected ${name}`);
    }

    const expected = SCALAR_TYPE[isScalar(name) ? name : "json"];

    if (name !== "json" && typeof value !== expected) {
      throw new TypeError(`${path} is ${describe(value)}, expected ${name}`);
    }

    return value;
  }

  if (isItemType(type)) {
    if (!Array.isArray(value)) {
      throw new TypeError(`${path} is ${describe(value)}, expected an array`);
    }

    return value.map((each, index) =>
      decodeAt(type[0], each, `${path}[${index}]`),
    );
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${path} is ${describe(value)}, expected an object`);
  }

  const record: Record<string, unknown> = { ...value };
  const out: Record<string, unknown> = {};

  for (const [key, each] of Object.entries(type)) {
    out[key] = decodeAt(each, record[key], `${path}.${key}`);
  }

  return out;
}

/**
 * Checks a read's JSON against its declared type and returns it typed. Throws a
 * `TypeError` naming the path that differs, which the block client reports as
 * an error result.
 */
export function decodeRead<T>(type: ReadType, value: unknown, name: string): T {
  // SAFETY: decodeAt rebuilt the value from `type`; the caller names `T` from the same descriptor.
  return decodeAt(type, value, name) as T;
}
