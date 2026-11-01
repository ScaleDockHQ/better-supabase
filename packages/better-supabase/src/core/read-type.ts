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

/** Whether `value` is a well-formed type. */
export function isReadType(value: unknown): value is ReadType {
  if (typeof value === "string") {
    return isScalar(value.endsWith("?") ? value.slice(0, -1) : value);
  }

  if (Array.isArray(value)) {
    return value.length === 1 && isReadType(value[0]);
  }

  return (
    typeof value === "object" &&
    value !== null &&
    Object.values(value).every((each) => isReadType(each))
  );
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
