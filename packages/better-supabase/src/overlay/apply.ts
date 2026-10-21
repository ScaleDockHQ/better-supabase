import type { SpecDiagnostic } from "../spec/format.ts";
import type { PathSegment } from "./path.ts";
import type {
  ApplyOverlayOptions,
  Overlay,
  OverlayAction,
  OverlayResult,
} from "./types.ts";

import { decodePointerToken, parseNormalizedPath } from "./path.ts";

type JsonObject = Record<string, unknown>;

type Minor = 0 | 1 | 2;

const ALLOW_EMPTY = "x-better-supabase-allow-empty";
const REF_PREFIX = "#/components/actions/";

export const isObject = (value: unknown): value is JsonObject =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isArray = (value: unknown): value is unknown[] => Array.isArray(value);

type Kind = "object" | "array" | "primitive";

const kindOf = (value: unknown): Kind =>
  Array.isArray(value) ? "array" : isObject(value) ? "object" : "primitive";

function readMinor(version: unknown): Minor | undefined {
  if (typeof version !== "string") {
    return undefined;
  }

  const match = /^1\.([012])\.\d+$/.exec(version);

  if (!match) {
    return undefined;
  }

  const minor = Number(match[1]);

  return minor === 0 || minor === 1 || minor === 2 ? minor : undefined;
}

/** A plain action after reusable references are expanded. */
type ResolvedAction = OverlayAction & { readonly [ALLOW_EMPTY]?: boolean };

/**
 * An Action Object needs a string target; the other fields are read
 * defensively.
 */
export const isAction = (
  entry: JsonObject,
): entry is JsonObject & ResolvedAction => typeof entry["target"] === "string";

export interface Reporter {
  readonly prefix: string;
  readonly diagnostics: SpecDiagnostic[];
}

function report(
  reporter: Reporter,
  severity: SpecDiagnostic["severity"],
  code: string,
  message: string,
  pointer: string,
): void {
  reporter.diagnostics.push({
    code,
    severity,
    message,
    pointer: `${reporter.prefix}${pointer}`,
  });
}

/**
 * Expands a Reusable Action Reference (Overlay 1.2 § 4.5.6) into a plain
 * action: the referenced `fields`, then the reference's own fields on top.
 */
export function resolveReference(
  overlay: Overlay,
  entry: JsonObject,
  pointer: string,
  reporter: Reporter,
): JsonObject | undefined {
  const { $ref: ref, ...own } = entry;

  if (typeof ref !== "string" || !ref.startsWith(REF_PREFIX)) {
    report(
      reporter,
      "error",
      "overlay-ref-unresolved",
      `The reusable action reference ${String(ref)} does not point under ${REF_PREFIX}`,
      pointer,
    );

    return undefined;
  }

  const name = decodePointerToken(ref.slice(REF_PREFIX.length));

  const components: unknown =
    "components" in overlay ? overlay.components : undefined;

  const reusables = isObject(components) ? components["actions"] : undefined;

  const reusable =
    isObject(reusables) && Object.hasOwn(reusables, name)
      ? reusables[name]
      : undefined;

  if (!isObject(reusable)) {
    report(
      reporter,
      "error",
      "overlay-ref-unresolved",
      `The reusable action ${ref} does not exist in components.actions`,
      pointer,
    );

    return undefined;
  }

  const fields: JsonObject = isObject(reusable["fields"])
    ? { ...reusable["fields"] }
    : {};

  if ("target" in fields) {
    report(
      reporter,
      "warning",
      "overlay-invalid-action",
      `The reusable action ${ref} sets target, which only the reference may set; it is ignored`,
      pointer,
    );
    delete fields["target"];
  }

  return { ...fields, ...own };
}

function resolve(
  document: unknown,
  segments: readonly PathSegment[],
): { parent: unknown; key: PathSegment | undefined; value: unknown } {
  let parent: unknown = undefined;
  let key: PathSegment | undefined = undefined;
  let value = document;

  for (const segment of segments) {
    parent = value;
    key = segment;
    value =
      typeof segment === "number"
        ? Array.isArray(value)
          ? value[segment]
          : undefined
        : isObject(value)
          ? value[segment]
          : undefined;
  }

  return { parent, key, value };
}

const escapeToken = (segment: PathSegment): string =>
  `/${String(segment).replaceAll("~", "~0").replaceAll("/", "~1")}`;

const toPointer = (segments: readonly PathSegment[]): string =>
  segments.map(escapeToken).join("");

/**
 * Merges `source` into `target` recursively (§ 4.5.4.1) and collects the
 * conflicting pointers.
 */
function mergeInto(
  target: JsonObject,
  source: JsonObject,
  at: string,
  conflicts: string[],
): void {
  for (const [key, value] of Object.entries(source)) {
    if (!Object.hasOwn(target, key)) {
      target[key] = value;
      continue;
    }

    const current = target[key];

    if (kindOf(current) !== kindOf(value)) {
      conflicts.push(`${at}${escapeToken(key)}`);
      continue;
    }

    if (isObject(current) && isObject(value)) {
      mergeInto(current, value, `${at}${escapeToken(key)}`, conflicts);
    } else if (isArray(current) && isArray(value)) {
      current.push(...value);
    } else {
      target[key] = value;
    }
  }
}

interface State {
  document: unknown;
}

function select(
  state: State,
  expression: string,
  options: ApplyOverlayOptions,
  reporter: Reporter,
  pointer: string,
  field: string,
): PathSegment[][] | undefined {
  try {
    return options.jsonpath
      .paths(state.document, expression)
      .map(parseNormalizedPath);
  } catch (error) {
    report(
      reporter,
      "error",
      "overlay-invalid-target",
      `The ${field} ${JSON.stringify(expression)} is not a valid RFC 9535 query: ${error instanceof Error ? error.message : String(error)}`,
      pointer,
    );

    return undefined;
  }
}

function removeNodes(
  state: State,
  targets: readonly PathSegment[][],
  reporter: Reporter,
  pointer: string,
): void {
  const fromArrays = new Map<unknown[], number[]>();

  for (const segments of targets) {
    const { parent, key } = resolve(state.document, segments);

    if (key === undefined) {
      report(
        reporter,
        "error",
        "overlay-invalid-action",
        "The action removes the document root, which is not allowed",
        pointer,
      );
      continue;
    }

    if (Array.isArray(parent) && typeof key === "number") {
      const indexes = fromArrays.get(parent) ?? [];
      indexes.push(key);
      fromArrays.set(parent, indexes);
    } else if (isObject(parent) && typeof key === "string") {
      delete parent[key];
    }
  }

  for (const [array, indexes] of fromArrays) {
    for (const index of [...new Set(indexes)].toSorted((a, b) => b - a)) {
      array.splice(index, 1);
    }
  }
}

function updateNodes(
  state: State,
  targets: readonly PathSegment[][],
  value: unknown,
  reporter: Reporter,
  pointer: string,
): void {
  const nodes = targets.map((segments) => ({
    segments,
    ...resolve(state.document, segments),
  }));

  const kinds = new Set(nodes.map((node) => kindOf(node.value)));

  if (kinds.size > 1) {
    report(
      reporter,
      "error",
      "overlay-mixed-targets",
      `The target selects ${[...kinds].join(" and ")} nodes; an update needs nodes of one kind`,
      pointer,
    );

    return;
  }

  const valueKind = kindOf(value);

  for (const node of nodes) {
    const copy = structuredClone(value);
    const at = toPointer(node.segments) || "the root";

    if (isArray(node.value)) {
      if (isArray(copy)) {
        node.value.push(...copy);
      } else {
        node.value.push(copy);
      }

      continue;
    }

    if (isObject(node.value)) {
      if (!isObject(copy)) {
        report(
          reporter,
          "error",
          "overlay-merge-conflict",
          `Cannot merge a${valueKind === "array" ? "n array" : " primitive"} into the object at ${at}`,
          pointer,
        );
        continue;
      }

      const conflicts: string[] = [];
      mergeInto(node.value, copy, toPointer(node.segments), conflicts);

      for (const conflict of conflicts) {
        report(
          reporter,
          "error",
          "overlay-merge-conflict",
          `Cannot merge values of different kinds at ${conflict}`,
          pointer,
        );
      }

      continue;
    }

    if (valueKind !== "primitive") {
      report(
        reporter,
        "error",
        "overlay-merge-conflict",
        `Cannot replace the primitive at ${at} with a${valueKind === "array" ? "n array" : "n object"}`,
        pointer,
      );
      continue;
    }

    if (node.key === undefined) {
      state.document = copy;
    } else if (Array.isArray(node.parent) && typeof node.key === "number") {
      node.parent[node.key] = copy;
    } else if (isObject(node.parent) && typeof node.key === "string") {
      node.parent[node.key] = copy;
    }
  }
}

function runAction(
  state: State,
  action: ResolvedAction,
  minor: Minor,
  options: ApplyOverlayOptions,
  reporter: Reporter,
  pointer: string,
): void {
  const usesCopy =
    action.remove !== true &&
    action.update === undefined &&
    action.copy !== undefined;

  if (usesCopy && minor === 0) {
    report(
      reporter,
      "error",
      "overlay-version-feature",
      "copy needs Overlay 1.1 or later; the action is skipped",
      pointer,
    );

    return;
  }

  const targets = select(
    state,
    action.target,
    options,
    reporter,
    pointer,
    "target",
  );

  if (!targets) {
    return;
  }

  if (targets.length === 0) {
    if (action[ALLOW_EMPTY] !== true && options.allowEmpty !== true) {
      report(
        reporter,
        "error",
        "overlay-no-match",
        `The target ${action.target} selects no nodes; set ${ALLOW_EMPTY}: true on the action if that is expected`,
        pointer,
      );
    }

    return;
  }

  if (action.remove === true) {
    removeNodes(state, targets, reporter, pointer);

    return;
  }

  if (action.update !== undefined) {
    updateNodes(state, targets, action.update, reporter, pointer);

    return;
  }

  if (typeof action.copy === "string") {
    const sources = select(
      state,
      action.copy,
      options,
      reporter,
      pointer,
      "copy source",
    );

    if (!sources) {
      return;
    }

    const [source] = sources;

    if (sources.length !== 1 || !source) {
      report(
        reporter,
        "error",
        "overlay-copy-source",
        `The copy source ${action.copy} selects ${sources.length} nodes; it must select exactly one`,
        pointer,
      );

      return;
    }

    updateNodes(
      state,
      targets,
      resolve(state.document, source).value,
      reporter,
      pointer,
    );

    return;
  }

  report(
    reporter,
    "warning",
    "overlay-empty-action",
    "The action has no update, copy or remove, so it changes nothing",
    pointer,
  );
}

/** Applies one overlay to `state.document` in place. */
function applyInPlace(
  state: State,
  overlay: Overlay,
  options: ApplyOverlayOptions,
  reporter: Reporter,
): void {
  const minor = readMinor(overlay.overlay);

  if (minor === undefined) {
    report(
      reporter,
      "error",
      "overlay-version-unsupported",
      `Overlay version ${overlay.overlay} is not supported; use 1.0.x, 1.1.x or 1.2.x`,
      "/overlay",
    );

    return;
  }

  if (!Array.isArray(overlay.actions)) {
    report(
      reporter,
      "error",
      "overlay-invalid-action",
      "The overlay has no actions array",
      "/actions",
    );

    return;
  }

  const actions: readonly unknown[] = overlay.actions;

  for (const [index, entry] of actions.entries()) {
    const pointer = `/actions/${index}`;

    if (!isObject(entry)) {
      report(
        reporter,
        "error",
        "overlay-invalid-action",
        "The action is not an object",
        pointer,
      );
      continue;
    }

    if ("$ref" in entry && minor < 2) {
      report(
        reporter,
        "warning",
        "overlay-version-feature",
        `Reusable actions need Overlay 1.2; the reference is expanded for this ${overlay.overlay} overlay`,
        pointer,
      );
    }

    const action =
      "$ref" in entry
        ? resolveReference(overlay, entry, pointer, reporter)
        : entry;

    if (!action) {
      continue;
    }

    if (!isAction(action)) {
      report(
        reporter,
        "error",
        "overlay-invalid-action",
        "The action has no target",
        pointer,
      );
      continue;
    }

    runAction(state, action, minor, options, reporter, pointer);
  }
}

/**
 * Applies an Overlay 1.0, 1.1 or 1.2 document to `document` and returns a new
 * document. The input is cloned once with `structuredClone` and never changed;
 * each target runs once through `options.jsonpath`.
 *
 * Actions run in order, each on the result of the previous one (Overlay §
 * 4.5.1.1). `update` merges objects, concatenates or appends to arrays and
 * replaces primitives; `remove` deletes the selected nodes; `copy` (1.1 and
 * later) uses the value of the single node its query selects. Reusable action
 * references (1.2) are expanded, with a warning when the overlay declares 1.0
 * or 1.1.
 *
 * Problems never throw: they are diagnostics, and the failing action is
 * skipped. A target that selects nothing reports `overlay-no-match` as an error
 * unless the action sets `x-better-supabase-allow-empty: true` or the options
 * set `allowEmpty`. The other codes are `overlay-invalid-target`,
 * `overlay-invalid-action`, `overlay-mixed-targets`, `overlay-merge-conflict`,
 * `overlay-copy-source`, `overlay-ref-unresolved`, `overlay-version-feature`,
 * `overlay-version-unsupported` and `overlay-empty-action`.
 *
 * The result keeps the input's type; an overlay that changes the shape needs
 * the caller to narrow it.
 *
 * @example
 *   const jsonpath = await loadJsonPath();
 *   const { document, diagnostics } = applyOverlay(openapi, overlay, {
 *     jsonpath,
 *   });
 */
export function applyOverlay<T>(
  document: T,
  overlay: Overlay,
  options: ApplyOverlayOptions,
): OverlayResult<T> {
  return run(document, [overlay], options, () => "");
}

/**
 * Applies overlays in order, each to the result of the previous one, with a
 * single clone of the input. Diagnostic pointers start with the overlay's index
 * (`/1/actions/0`).
 */
export function applyOverlays<T>(
  document: T,
  overlays: readonly Overlay[],
  options: ApplyOverlayOptions,
): OverlayResult<T> {
  return run(document, overlays, options, (index) => `/${index}`);
}

function run<T>(
  document: T,
  overlays: readonly Overlay[],
  options: ApplyOverlayOptions,
  prefix: (index: number) => string,
): OverlayResult<T> {
  const state: State = { document: structuredClone(document) };
  const diagnostics: SpecDiagnostic[] = [];

  for (const [index, overlay] of overlays.entries()) {
    applyInPlace(state, overlay, options, {
      prefix: prefix(index),
      diagnostics,
    });
  }

  // SAFETY: the clone starts as a T; overlays that change its shape are the caller's to narrow (see applyOverlay).
  return { document: state.document as T, diagnostics };
}
