import { parse, stringify } from "yaml";

import { serializeDocument } from "../../spec/index.ts";

export type SpecSerialization = "json" | "yaml";

/** `yaml` for `.yaml` and `.yml` files, otherwise `json`. */
export function serializationOf(path: string): SpecSerialization {
  return /\.ya?ml$/i.test(path) ? "yaml" : "json";
}

/**
 * The document as text. JSON keeps the generated key order and ends in a
 * newline; YAML is YAML 1.2 with the same order, no anchors and no line
 * folding, so the same document always gives the same bytes.
 */
export function documentText(
  document: unknown,
  serialization: SpecSerialization,
): string {
  const json = serializeDocument(document);
  if (serialization === "json") return json;
  const plain: unknown = JSON.parse(json);
  return stringify(plain, {
    version: "1.2",
    lineWidth: 0,
    aliasDuplicateObjects: false,
  });
}

/** Parses a JSON or YAML file (an overlay, a fragment) by its extension. */
export function parseDocumentText(path: string, text: string): unknown {
  return parseAs(serializationOf(path), text);
}

export function parseAs(
  serialization: SpecSerialization,
  text: string,
): unknown {
  if (serialization === "yaml") {
    const value: unknown = parse(text, { version: "1.2" });
    return value;
  }
  const value: unknown = JSON.parse(text);
  return value;
}

/** A property of a parsed document, or `undefined` when the value is not an object. */
export function fieldOf(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.getOwnPropertyDescriptor(value, key)?.value
    : undefined;
}
