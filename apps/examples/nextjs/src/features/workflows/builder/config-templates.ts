import * as v from "valibot";

/**
 * Data mapping for node config. A string value may hold `{{ path }}` markers
 * that read the run's data: `input.text` is the trigger's input,
 * `results.<node>.<field>` the output of a node that ran before. The editor's
 * data picker writes the markers; the steps resolve them before they run. No
 * imports beyond valibot, so the workflow bundle and the browser share it.
 */

/** What a node config, a run input and a node output hold: plain JSON. */
export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | JsonObject;

export interface JsonObject {
  [key: string]: JsonValue | undefined;
}

export const JsonSchema: v.GenericSchema<JsonValue> = v.lazy(() =>
  v.union([
    v.string(),
    v.number(),
    v.boolean(),
    v.null(),
    v.array(JsonSchema),
    v.record(v.string(), v.optional(JsonSchema)),
  ]),
);

export const JsonObjectSchema: v.GenericSchema<JsonObject> = v.record(
  v.string(),
  v.optional(JsonSchema),
);

export interface TemplateScope {
  readonly input: JsonValue;
  readonly results: JsonObject;
}

const MARKER = /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/gu;
const WHOLE = /^\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}$/u;

/** Reads `input.a.b` or `results.node.a` from the run's data. */
export function readTemplatePath(
  scope: TemplateScope,
  path: string,
): JsonValue | undefined {
  const [root, ...rest] = path.split(".");

  if (root !== "input" && root !== "results") {
    return undefined;
  }

  let value: JsonValue | undefined =
    root === "input" ? scope.input : scope.results;

  for (const key of rest) {
    if (Array.isArray(value)) {
      value = value[Number(key)];
    } else if (v.is(JsonObjectSchema, value)) {
      value = value[key];
    } else {
      return undefined;
    }
  }

  return value;
}

const asText = (value: JsonValue | undefined): string => {
  if (value === undefined || value === null) {
    return "";
  }

  return v.is(v.string(), value) ? value : JSON.stringify(value);
};

/**
 * A config value with its markers filled in. A string that is one marker keeps
 * the value's type (a list stays a list); markers inside longer text become
 * text. Objects and lists are resolved deeply.
 */
export function resolveTemplates(
  value: JsonValue,
  scope: TemplateScope,
): JsonValue {
  if (v.is(v.string(), value)) {
    const whole = WHOLE.exec(value);

    if (whole?.[1] !== undefined) {
      return readTemplatePath(scope, whole[1]) ?? null;
    }

    return value.replaceAll(MARKER, (_, path: string) =>
      asText(readTemplatePath(scope, path)),
    );
  }

  if (Array.isArray(value)) {
    return value.map((item) => resolveTemplates(item, scope));
  }

  if (v.is(JsonObjectSchema, value)) {
    const resolved: JsonObject = {};

    for (const [key, item] of Object.entries(value)) {
      if (item !== undefined) {
        resolved[key] = resolveTemplates(item, scope);
      }
    }

    return resolved;
  }

  return value;
}

/** The paths a config value reads, in order of appearance. */
export function templatePaths(value: JsonValue): readonly string[] {
  if (v.is(v.string(), value)) {
    return [...value.matchAll(MARKER)].flatMap((match) =>
      match[1] === undefined ? [] : [match[1]],
    );
  }

  if (Array.isArray(value)) {
    return value.flatMap((item) => templatePaths(item));
  }

  if (v.is(JsonObjectSchema, value)) {
    return Object.values(value).flatMap((item) =>
      item === undefined ? [] : templatePaths(item),
    );
  }

  return [];
}

/** The marker text for a path. */
export const templateMarker = (path: string): string => `{{${path}}}`;
