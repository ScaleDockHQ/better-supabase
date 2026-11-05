import type { BlockSqlContext } from "../context.ts";
import type {
  DocumentVariable,
  DocumentVariableType,
} from "./document-templates-values.ts";

import { sqlIdent } from "../../core/template.ts";
import { DOCUMENT_TYPES } from "./document-templates-values.ts";

/** A document type the app defined in `options.documentTypes`. */
export interface AppDocumentTypeSql {
  readonly name: string;
  /** The quoted, schema-qualified builder function. */
  readonly builder: string;
  readonly variables: readonly DocumentVariable[];
}

const TYPE_NAME = /^[a-z][a-z0-9_]{0,63}$/;
const IDENTIFIER = /^[a-z_][a-z0-9_]{0,62}$/;

const VARIABLE_PATH =
  /^[A-Za-z_][A-Za-z0-9_]*(?:\[\])?(?:\.[A-Za-z_][A-Za-z0-9_]*(?:\[\])?)*$/;

const KINDS: ReadonlySet<string> = new Set<DocumentVariableType>([
  "string",
  "number",
  "boolean",
  "money",
  "date",
  "object",
  "list",
]);

function record(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`document-templates: ${what} must be an object`);
  }

  // SAFETY: narrowed above to a non-null, non-array object.
  return value as Record<string, unknown>;
}

function builderOf(name: string, value: unknown): string {
  const parts = typeof value === "string" ? value.split(".") : [];

  if (parts.length !== 2 || !parts.every((part) => IDENTIFIER.test(part))) {
    throw new TypeError(
      `document-templates: documentTypes.${name}.function must be "schema.name" in lower case`,
    );
  }

  return parts.map((part) => sqlIdent(part)).join(".");
}

function variableOf(name: string, value: unknown): DocumentVariable {
  const item = record(value, `a variable of documentTypes.${name}`);
  const { path, type, description } = item;

  if (typeof path !== "string" || !VARIABLE_PATH.test(path)) {
    throw new TypeError(
      `document-templates: documentTypes.${name} has a variable path that is not a dotted name`,
    );
  }

  if (typeof type !== "string" || !KINDS.has(type)) {
    throw new TypeError(
      `document-templates: documentTypes.${name}.${path} needs a type of ${[...KINDS].join(", ")}`,
    );
  }

  return {
    path,
    // SAFETY: checked against KINDS above.
    type: type as DocumentVariableType,
    description: typeof description === "string" ? description : path,
  };
}

/** The checked `options.documentTypes`, in name order. */
export function appDocumentTypes(
  ctx: BlockSqlContext,
): readonly AppDocumentTypeSql[] {
  const raw = ctx.option("documentTypes");

  if (raw === undefined) {
    return [];
  }

  const found: AppDocumentTypeSql[] = [];

  for (const [name, definition] of Object.entries(
    record(raw, "documentTypes"),
  ).toSorted(([a], [b]) => a.localeCompare(b))) {
    if (!TYPE_NAME.test(name)) {
      throw new TypeError(
        `document-templates: document type "${name}" must be lower case letters, digits and _, from a letter`,
      );
    }

    if (DOCUMENT_TYPES.some((type) => type === name)) {
      throw new TypeError(
        `document-templates: "${name}" is a built-in document type`,
      );
    }

    const entry = record(definition, `documentTypes.${name}`);
    const list = entry["variables"];

    if (!Array.isArray(list) || list.length === 0) {
      throw new TypeError(
        `document-templates: documentTypes.${name}.variables must list at least one variable`,
      );
    }

    found.push({
      name,
      builder: builderOf(name, entry["function"]),
      variables: list.map((item: unknown) => variableOf(name, item)),
    });
  }

  return found;
}

/** Every document type name: the built-in ones, then the app's. */
export function documentTypeNames(ctx: BlockSqlContext): readonly string[] {
  return [...DOCUMENT_TYPES, ...appDocumentTypes(ctx).map((type) => type.name)];
}
