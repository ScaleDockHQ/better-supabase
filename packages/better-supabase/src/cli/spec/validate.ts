import Ajv, { type ErrorObject, type ValidateFunction } from "ajv";
import addFormats from "ajv-formats";
import Ajv2020 from "ajv/dist/2020.js";

import type { SpecDiagnostic } from "../../spec/index.ts";
import type { OfficialSchema } from "./schemas.ts";

import { officialSchema } from "./schemas.ts";

/** At most this many schema errors per document; the rest are counted. */
const MAX_ERRORS = 50;

type Json = Record<string, unknown>;

const isJson = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

let engines: { readonly draft7: Ajv; readonly draft2020: Ajv2020 } | undefined;

function enginesOf(): { readonly draft7: Ajv; readonly draft2020: Ajv2020 } {
  if (!engines) {
    const draft7 = new Ajv({ strict: false, allErrors: true });
    const draft2020 = new Ajv2020({ strict: false, allErrors: true });
    addFormats(draft7);
    addFormats(draft2020);
    // OpenAPI 3.1 and 3.2 name media ranges with a format Ajv doesn't know.
    draft2020.addFormat("media-range", true);
    engines = { draft7, draft2020 };
  }

  return engines;
}

/**
 * Draft-04 to draft-07, enough for the OpenAPI 3.0 schema: `id` becomes
 * `$id`, and boolean `exclusiveMinimum`/`exclusiveMaximum` fold into the
 * number they qualify. Changes the copy in place.
 */
function fromDraft04(node: unknown, root = true): void {
  if (Array.isArray(node)) {
    for (const item of node) {
      fromDraft04(item, false);
    }

    return;
  }

  if (!isJson(node)) {
    return;
  }

  if (root) {
    delete node["$schema"];

    if (typeof node["id"] === "string") {
      node["$id"] = node["id"];
      delete node["id"];
    }
  }

  for (const [bound, exclusive] of [
    ["minimum", "exclusiveMinimum"],
    ["maximum", "exclusiveMaximum"],
  ] as const) {
    if (typeof node[exclusive] !== "boolean") {
      continue;
    }

    if (node[exclusive] && typeof node[bound] === "number") {
      node[exclusive] = node[bound];
      delete node[bound];
    } else {
      delete node[exclusive];
    }
  }

  for (const [key, value] of Object.entries(node)) {
    if (key !== "enum" && key !== "const" && key !== "default") {
      fromDraft04(value, false);
    }
  }
}

/**
 * Ajv resolves `$dynamicRef` against the wrong scope in the OpenAPI
 * schemas. With one `$dynamicAnchor` of a name in the document, a
 * `$dynamicRef` to it means the same as a `$ref` to the anchor's location.
 */
function staticDynamicRefs(schema: Json): void {
  const anchors = new Map<string, string>();

  const find = (node: unknown, pointer: string): void => {
    if (!isJson(node) && !Array.isArray(node)) {
      return;
    }

    for (const [key, value] of Object.entries(node)) {
      if (key === "$dynamicAnchor" && typeof value === "string") {
        anchors.set(value, `#${pointer}`);
      } else {
        find(value, `${pointer}/${key}`);
      }
    }
  };

  const rewrite = (node: unknown): void => {
    if (Array.isArray(node)) {
      for (const item of node) {
        rewrite(item);
      }

      return;
    }

    if (!isJson(node)) {
      return;
    }

    const dynamic = node["$dynamicRef"];

    const target =
      typeof dynamic === "string" ? anchors.get(dynamic.slice(1)) : undefined;

    if (target !== undefined) {
      delete node["$dynamicRef"];
      node["$ref"] = target;
    }

    for (const value of Object.values(node)) {
      rewrite(value);
    }
  };

  find(schema, "");
  rewrite(schema);
}

const META_SCHEMA = /^https?:\/\/json-schema\.org\/draft-07\/schema#?$/;

/**
 * The AsyncAPI bundles embed a copy of the draft-07 meta-schema under its
 * own `$id`, which Ajv already registers. Dropping the copy lets every
 * `$ref` to it resolve to Ajv's built-in one.
 */
function dropBundledMetaSchemas(schema: Json): void {
  const definitions = schema["definitions"];

  if (!isJson(definitions)) {
    return;
  }

  for (const [key, value] of Object.entries(definitions)) {
    if (
      isJson(value) &&
      typeof value["$id"] === "string" &&
      META_SCHEMA.test(value["$id"])
    ) {
      delete definitions[key];
    }
  }
}

const compiled = new Map<string, Promise<ValidateFunction>>();

async function compile(official: OfficialSchema): Promise<ValidateFunction> {
  const loaded = await official.load();

  if (!isJson(loaded)) {
    throw new TypeError(`The vendored schema ${official.id} is not an object`);
  }

  const schema = structuredClone(loaded);
  const { draft7, draft2020 } = enginesOf();

  if (official.dialect === "2020-12") {
    staticDynamicRefs(schema);

    return draft2020.compile(schema);
  }

  if (official.dialect === "draft-04") {
    fromDraft04(schema);
  } else {
    dropBundledMetaSchemas(schema);
  }

  return draft7.compile(schema);
}

function validatorFor(official: OfficialSchema): Promise<ValidateFunction> {
  let hit = compiled.get(official.id);

  if (!hit) {
    hit = compile(official);
    compiled.set(official.id, hit);
  }

  return hit;
}

function describe(error: ErrorObject): string {
  const params = Object.entries(error.params)
    .filter(([, value]) => typeof value !== "object")
    .map(([key, value]) => `${key}: ${String(value)}`)
    .join(", ");

  return `${error.message ?? "is invalid"}${params ? ` (${params})` : ""}`;
}

/**
 * Checks a document against the official schema of its format version.
 * Reports `schema-invalid` errors, or one `schema-unavailable` info when no
 * schema is vendored for the version (the 3.3 preview, third-party formats).
 */
export async function validateDocument(
  format: string,
  version: string,
  document: unknown,
): Promise<SpecDiagnostic[]> {
  const official = officialSchema(format, version);

  if (!official) {
    return [
      {
        code: "schema-unavailable",
        severity: "info",
        message: `No official schema is bundled for ${format} ${version}; only the semantic checks ran`,
      },
    ];
  }

  const validate = await validatorFor(official);

  if (validate(document)) {
    return [];
  }

  const seen = new Set<string>();
  const diagnostics: SpecDiagnostic[] = [];

  for (const error of validate.errors ?? []) {
    const message = describe(error);
    const key = `${error.instancePath}\u0000${message}`;

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    diagnostics.push({
      code: "schema-invalid",
      severity: "error",
      message: `Does not match the ${format} ${version} schema: ${message}`,
      pointer: error.instancePath,
    });
  }

  if (diagnostics.length <= MAX_ERRORS) {
    return diagnostics;
  }

  return [
    ...diagnostics.slice(0, MAX_ERRORS),
    {
      code: "schema-invalid",
      severity: "error",
      message: `${diagnostics.length - MAX_ERRORS} more schema errors not shown`,
    },
  ];
}
