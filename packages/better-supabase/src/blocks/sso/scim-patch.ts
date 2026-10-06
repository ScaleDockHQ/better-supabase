/** SCIM PATCH (RFC 7644 §3.5.2) over resource JSON, applied to a copy. */

import type { ScimAttribute } from "./scim-schema.ts";

import { isRecord } from "../shared.ts";
import { matches, parseFilter, type ScimFilter } from "./scim-filter.ts";

/** A PATCH the service provider rejects, with its `scimType`. */
export class ScimPatchError extends Error {
  override readonly name = "ScimPatchError";
  readonly scimType:
    | "invalidPath"
    | "noTarget"
    | "mutability"
    | "invalidSyntax"
    | "invalidValue"
    | "invalidFilter";

  constructor(scimType: ScimPatchError["scimType"], message: string) {
    super(message);
    this.scimType = scimType;
  }
}

interface Path {
  readonly attribute: ScimAttribute;
  readonly filter: ScimFilter | undefined;
  readonly sub: ScimAttribute | undefined;
}

type Doc = Record<string, unknown>;

const PATH = /^([A-Za-z$][\w$-]*)(?:\[(.*)\])?(?:\.([A-Za-z$][\w$-]*))?$/s;

const find = (
  attributes: readonly ScimAttribute[] | undefined,
  name: string,
): ScimAttribute | undefined =>
  attributes?.find((a) => a.name.toLowerCase() === name.toLowerCase());

function parsePath(
  raw: string,
  urn: string,
  attributes: readonly ScimAttribute[],
): Path {
  const prefix = `${urn.toLowerCase()}:`;
  const local = raw.toLowerCase().startsWith(prefix)
    ? raw.slice(prefix.length)
    : raw;
  const match = PATH.exec(local);
  if (!match) throw new ScimPatchError("invalidPath", `Invalid path ${raw}`);
  const [, name = "", filterText, subName] = match;
  const attribute = find(attributes, name);
  if (!attribute) {
    throw new ScimPatchError("invalidPath", `Unknown attribute ${name}`);
  }
  if (attribute.mutability === "readOnly") {
    throw new ScimPatchError("mutability", `${attribute.name} is read-only`);
  }
  let filter: ScimFilter | undefined;
  if (filterText !== undefined) {
    if (!attribute.multiValued) {
      throw new ScimPatchError(
        "invalidPath",
        `${attribute.name} is not multi-valued`,
      );
    }
    try {
      filter = parseFilter(filterText);
    } catch (cause) {
      throw new ScimPatchError(
        "invalidFilter",
        cause instanceof Error ? cause.message : String(cause),
      );
    }
  }
  let sub: ScimAttribute | undefined;
  if (subName !== undefined) {
    sub = find(attribute.subAttributes, subName);
    if (!sub) {
      throw new ScimPatchError(
        "invalidPath",
        `Unknown attribute ${attribute.name}.${subName}`,
      );
    }
  }
  return { attribute, filter, sub };
}

const itemsOf = (value: unknown): Doc[] => {
  const items: readonly unknown[] = Array.isArray(value) ? value : [value];
  return items.map((item) => (isRecord(item) ? { ...item } : { value: item }));
};

const without = (item: Doc, key: string): Doc =>
  Object.fromEntries(Object.entries(item).filter(([name]) => name !== key));

const sameValue = (a: Doc, b: Doc): boolean =>
  String(a["value"]).toLowerCase() === String(b["value"]).toLowerCase();

/** Keeps one `primary: true` value: the last one set. */
function onePrimary(items: Doc[]): Doc[] {
  const last = items.findLastIndex((item) => item["primary"] === true);
  return items.map((item, index) =>
    index !== last && item["primary"] === true
      ? { ...item, primary: false }
      : item,
  );
}

function apply(
  doc: Doc,
  op: "add" | "replace" | "remove",
  path: Path,
  value: unknown,
): void {
  const { attribute, filter, sub } = path;
  const key = attribute.name;
  if (attribute.multiValued) {
    const current = Array.isArray(doc[key]) ? itemsOf(doc[key]) : [];
    if (filter === undefined) {
      if (sub !== undefined) {
        if (op === "remove") {
          doc[key] = current.map((item) => without(item, sub.name));
        } else {
          doc[key] =
            current.length === 0
              ? [{ [sub.name]: value }]
              : current.map((item) => ({ ...item, [sub.name]: value }));
        }
        return;
      }
      if (op === "remove") {
        if (value === undefined) {
          delete doc[key];
        } else {
          const gone = itemsOf(value);
          doc[key] = current.filter(
            (item) => !gone.some((other) => sameValue(item, other)),
          );
        }
        return;
      }
      const added = itemsOf(value);
      doc[key] = onePrimary(
        op === "replace"
          ? added
          : [
              ...current,
              ...added.filter(
                (item) => !current.some((other) => sameValue(item, other)),
              ),
            ],
      );
      return;
    }
    const hit = (item: Doc): boolean => matches(item, filter);
    if (op === "remove") {
      doc[key] =
        sub === undefined
          ? current.filter((item) => !hit(item))
          : current.map((item) => (hit(item) ? without(item, sub.name) : item));
      return;
    }
    if (!current.some(hit)) {
      throw new ScimPatchError(
        "noTarget",
        `No ${key} value matches the filter`,
      );
    }
    doc[key] = onePrimary(
      current.map((item) => {
        if (!hit(item)) return item;
        if (sub !== undefined) return { ...item, [sub.name]: value };
        if (!isRecord(value)) {
          throw new ScimPatchError("invalidValue", `${key} values are objects`);
        }
        return op === "replace" ? { ...value } : { ...item, ...value };
      }),
    );
    return;
  }
  if (sub !== undefined) {
    const inner = isRecord(doc[key]) ? { ...doc[key] } : {};
    if (op === "remove") delete inner[sub.name];
    else inner[sub.name] = value;
    doc[key] = inner;
    return;
  }
  if (op === "remove") {
    if (attribute.required) {
      throw new ScimPatchError("mutability", `${key} is required`);
    }
    delete doc[key];
    return;
  }
  if (attribute.type === "complex") {
    if (!isRecord(value)) {
      throw new ScimPatchError("invalidValue", `${key} is an object`);
    }
    doc[key] =
      op === "add" && isRecord(doc[key])
        ? { ...doc[key], ...value }
        : { ...value };
    return;
  }
  doc[key] = value;
}

const OPS = ["add", "replace", "remove"] as const;

/**
 * Applies a PatchOp body's `Operations` to a copy of `resource`, in order.
 * Throws `ScimPatchError`; the original is never changed.
 */
export function applyPatch(
  resource: Doc,
  body: unknown,
  urn: string,
  attributes: readonly ScimAttribute[],
  patchUrn: string,
): Doc {
  if (
    !isRecord(body) ||
    !Array.isArray(body["schemas"]) ||
    !body["schemas"].includes(patchUrn) ||
    !Array.isArray(body["Operations"])
  ) {
    throw new ScimPatchError(
      "invalidSyntax",
      `A PATCH body has schemas [${patchUrn}] and Operations`,
    );
  }
  const doc: Doc = structuredClone(resource);
  for (const operation of body["Operations"]) {
    if (!isRecord(operation)) {
      throw new ScimPatchError("invalidSyntax", "Each operation is an object");
    }
    const name = String(operation["op"]).toLowerCase();
    const op = OPS.find((candidate) => candidate === name);
    if (op === undefined) {
      throw new ScimPatchError(
        "invalidSyntax",
        `Unknown op ${String(operation["op"])}`,
      );
    }
    const value = operation["value"];
    const raw = operation["path"];
    if (raw !== undefined && typeof raw !== "string") {
      throw new ScimPatchError("invalidPath", "path is a string");
    }
    if (raw !== undefined && raw.length > 0) {
      apply(doc, op, parsePath(raw, urn, attributes), value);
      continue;
    }
    if (op === "remove") {
      throw new ScimPatchError("noTarget", "remove needs a path");
    }
    if (!isRecord(value)) {
      throw new ScimPatchError(
        "invalidValue",
        "Without a path the value is an object of attributes",
      );
    }
    for (const [key, inner] of Object.entries(value)) {
      if (key.toLowerCase() === urn.toLowerCase() && isRecord(inner)) {
        for (const [nested, nestedValue] of Object.entries(inner)) {
          apply(doc, op, parsePath(nested, urn, attributes), nestedValue);
        }
      } else if (key.toLowerCase() !== "schemas") {
        apply(doc, op, parsePath(key, urn, attributes), inner);
      }
    }
  }
  return doc;
}
