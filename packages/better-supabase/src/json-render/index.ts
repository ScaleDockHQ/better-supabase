import type { StandardSchemaV1 } from "@standard-schema/spec";

/**
 * The shapes of json-render's flat spec and its `data-spec` stream part, typed
 * structurally so `@json-render/core` stays an optional peer. The types accept
 * every spec `@json-render/core` produces.
 */
export interface JsonRenderElement {
  readonly type: string;
  readonly props?: Readonly<Record<string, unknown>>;
  readonly children?: readonly string[];
}

export interface JsonRenderSpec {
  readonly root: string;
  readonly elements: Readonly<Record<string, JsonRenderElement>>;
  readonly state?: Readonly<Record<string, unknown>>;
}

export interface JsonRenderPatch {
  readonly op: "add" | "remove" | "replace" | "move" | "copy" | "test";
  readonly path: string;
  readonly value?: unknown;
  readonly from?: string;
}

export type JsonRenderSpecPart =
  | { readonly type: "patch"; readonly patch: JsonRenderPatch }
  | { readonly type: "flat"; readonly spec: JsonRenderSpec }
  | {
      readonly type: "nested";
      readonly spec: Readonly<Record<string, unknown>>;
    };

/** A message part of a streamed spec. */
export interface JsonRenderPart {
  readonly type: "data-spec";
  readonly id?: string;
  readonly data: JsonRenderSpecPart;
}

/** The part of a `defineCatalog` result `validateSpec` calls. */
export interface JsonRenderCatalog {
  validate(spec: unknown): {
    readonly success: boolean;
    readonly error?: unknown;
  };
}

export type SpecIssue = {
  readonly code: string;
  readonly message: string;
  readonly path?: string;
};

export type SpecValidation =
  | { readonly ok: true; readonly spec: JsonRenderSpec }
  | { readonly ok: false; readonly issues: readonly SpecIssue[] };

type MessageLike = { readonly parts: readonly unknown[] };

const PART_TYPE = "data-spec";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const OPS: ReadonlySet<string> = new Set([
  "add",
  "remove",
  "replace",
  "move",
  "copy",
  "test",
]);

function isPatch(value: unknown): value is JsonRenderPatch {
  return (
    isRecord(value) &&
    typeof value["op"] === "string" &&
    OPS.has(value["op"]) &&
    typeof value["path"] === "string"
  );
}

export function isSpec(value: unknown): value is JsonRenderSpec {
  return (
    isRecord(value) &&
    typeof value["root"] === "string" &&
    isRecord(value["elements"])
  );
}

function specPartIssues(value: unknown): readonly StandardSchemaV1.Issue[] {
  if (!isRecord(value)) {
    return [{ message: "a spec part must be an object" }];
  }

  switch (value["type"]) {
    case "patch": {
      return isPatch(value["patch"])
        ? []
        : [
            {
              message: "a patch part needs an RFC 6902 operation",
              path: ["patch"],
            },
          ];
    }

    case "flat": {
      return isSpec(value["spec"])
        ? []
        : [
            {
              message: "a flat part needs a spec with root and elements",
              path: ["spec"],
            },
          ];
    }

    case "nested": {
      return isRecord(value["spec"])
        ? []
        : [{ message: "a nested part needs a spec object", path: ["spec"] }];
    }

    default: {
      return [
        { message: "the type must be patch, flat or nested", path: ["type"] },
      ];
    }
  }
}

const specPartSchema: StandardSchemaV1<unknown, JsonRenderSpecPart> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) => {
      const issues = specPartIssues(value);

      // SAFETY: specPartIssues checked the shape.
      return issues.length > 0
        ? { issues }
        : { value: value as JsonRenderSpecPart };
    },
  },
};

/**
 * The `dataSchemas` entry for `validateUIMessages`, so a stored message with a
 * `data-spec` part is checked on the way back in: `validateUIMessages({
 * messages, dataSchemas: specDataSchemas })`.
 */
export const specDataSchemas: {
  readonly spec: StandardSchemaV1<unknown, JsonRenderSpecPart>;
} = { spec: specPartSchema };

// An RFC 6901 pointer, split into unescaped segments.
function segments(pointer: string): string[] {
  if (pointer === "") {
    return [];
  }

  return pointer
    .slice(1)
    .split("/")
    .map((part) => part.replaceAll("~1", "/").replaceAll("~0", "~"));
}

const FORBIDDEN = new Set(["__proto__", "constructor", "prototype"]);

function clone<T>(value: T): T {
  return structuredClone(value);
}

function read(target: unknown, path: readonly string[]): unknown {
  let current = target;

  for (const key of path) {
    if (Array.isArray(current)) {
      current = current[Number(key)];
    } else if (isRecord(current)) {
      current = current[key];
    } else {
      return undefined;
    }
  }

  return current;
}

function write(
  root: Record<string, unknown>,
  path: readonly string[],
  op: "add" | "replace" | "remove",
  value: unknown,
): void {
  if (path.length === 0 || path.some((part) => FORBIDDEN.has(part))) {
    throw new TypeError("a patch path must name a key of the spec");
  }

  const parent = read(root, path.slice(0, -1));
  // The path is not empty here.
  const key = path.at(-1)!;

  if (Array.isArray(parent)) {
    const at = key === "-" ? parent.length : Number(key);

    if (op === "remove") {
      parent.splice(at, 1);
    } else if (op === "add") {
      parent.splice(at, 0, value);
    } else {
      parent[at] = value;
    }

    return;
  }

  if (!isRecord(parent)) {
    throw new TypeError(`no object at ${path.slice(0, -1).join("/")}`);
  }

  if (op === "remove") {
    delete parent[key];
  } else {
    parent[key] = value;
  }
}

/** Applies one RFC 6902 operation to a copy of the spec. */
export function applySpecPatch(
  spec: Readonly<Record<string, unknown>>,
  patch: JsonRenderPatch,
): Record<string, unknown> {
  // SAFETY: structuredClone of a plain object.
  const next = clone(spec) as Record<string, unknown>;
  const path = segments(patch.path);

  switch (patch.op) {
    case "add":
    case "replace": {
      write(next, path, patch.op, clone(patch.value));
      break;
    }

    case "remove": {
      write(next, path, "remove", undefined);
      break;
    }

    case "move":
    case "copy": {
      const from = segments(patch.from ?? "");
      const moved = clone(read(next, from));

      if (patch.op === "move") {
        write(next, from, "remove", undefined);
      }

      write(next, path, "add", moved);
      break;
    }

    case "test": {
      break;
    }

    default: {
      const never: never = patch.op;

      throw new TypeError(`unknown patch operation ${String(never)}`);
    }
  }

  return next;
}

const specOf = (part: unknown): JsonRenderSpecPart | undefined => {
  if (!isRecord(part) || part["type"] !== PART_TYPE) {
    return undefined;
  }

  // SAFETY: specPartIssues checked the shape.
  return specPartIssues(part["data"]).length === 0
    ? (part["data"] as JsonRenderSpecPart)
    : undefined;
};

/**
 * Folds the `data-spec` patch parts of a message into one `flat` part at the
 * place of the first, so the stored message holds the finished spec instead of
 * hundreds of patches. Other parts keep their order. Call it from the
 * assistant's `parts.compact`. A message with no spec parts is returned as is.
 */
export function collapseSpecParts<M extends MessageLike>(message: M): M {
  let spec: Record<string, unknown> | undefined;
  let first = -1;
  const kept: unknown[] = [];

  for (const part of message.parts) {
    const data = specOf(part);

    if (!data) {
      kept.push(part);

      continue;
    }

    if (first === -1) {
      first = kept.length;
      kept.push(undefined);
    }

    if (data.type === "patch") {
      spec = applySpecPatch(spec ?? { root: "", elements: {} }, data.patch);
    } else {
      // SAFETY: a spec part holds a plain object.
      spec = clone(data.spec) as Record<string, unknown>;
    }
  }

  if (
    first === -1 ||
    spec === undefined ||
    typeof spec["root"] !== "string" ||
    !isRecord(spec["elements"])
  ) {
    return message;
  }

  const flat: JsonRenderSpec = {
    root: spec["root"],
    // SAFETY: the patches built the elements; the model output was validated upstream.
    elements: spec["elements"] as JsonRenderSpec["elements"],
  };

  kept[first] = {
    type: PART_TYPE,
    data: { type: "flat", spec: flat },
  } satisfies JsonRenderPart;

  return { ...message, parts: kept };
}

/** The current spec of a message: the result of its spec parts, or undefined. */
export function specOfMessage(
  message: MessageLike,
): JsonRenderSpec | undefined {
  const collapsed = collapseSpecParts(message);

  for (const part of collapsed.parts) {
    const data = specOf(part);

    if (data?.type === "flat") {
      return data.spec;
    }
  }

  return undefined;
}

/**
 * Checks a spec before it is saved: the structure (a root that exists, children
 * that exist, no orphans) and, with a catalog, its components and props. The
 * catalog is the result of `defineCatalog` from `@json-render/core`.
 */
export function validateSpec(
  catalog: JsonRenderCatalog | undefined,
  spec: unknown,
): SpecValidation {
  if (!isSpec(spec)) {
    return {
      ok: false,
      issues: [
        { code: "invalid_spec", message: "a spec needs a root and elements" },
      ],
    };
  }

  const issues: SpecIssue[] = [];

  if (spec.elements[spec.root] === undefined) {
    issues.push({
      code: "root_not_found",
      message: `the root element ${spec.root} does not exist`,
      path: "/root",
    });
  }

  const reached = new Set<string>();

  const visit = (id: string): void => {
    if (reached.has(id)) {
      return;
    }

    reached.add(id);

    for (const child of spec.elements[id]?.children ?? []) {
      if (spec.elements[child] === undefined) {
        issues.push({
          code: "missing_child",
          message: `element ${id} lists the child ${child}, which does not exist`,
          path: `/elements/${id}/children`,
        });
      } else {
        visit(child);
      }
    }
  };

  visit(spec.root);

  for (const id of Object.keys(spec.elements)) {
    if (!reached.has(id)) {
      issues.push({
        code: "orphaned_element",
        message: `element ${id} is not reachable from the root`,
        path: `/elements/${id}`,
      });
    }
  }

  if (catalog) {
    const checked = catalog.validate(spec);

    if (!checked.success) {
      issues.push({
        code: "catalog",
        message:
          checked.error instanceof Error
            ? checked.error.message
            : "the spec does not match the catalog",
      });
    }
  }

  return issues.length > 0 ? { ok: false, issues } : { ok: true, spec };
}

/** The content of an ai-files document of kind `spec`: the spec as JSON text. */
export function specDocumentContent(spec: JsonRenderSpec): string {
  return JSON.stringify(spec);
}

/** Reads a `spec` document's content, or `undefined` when it isn't a spec. */
export function parseSpecDocument(content: string): JsonRenderSpec | undefined {
  try {
    const parsed: unknown = JSON.parse(content);

    return isSpec(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}
