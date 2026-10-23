import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type {
  JsonPathEngine,
  Overlay,
  OverlayEngine,
  SpecDiagnostic,
} from "../../spec/index.ts";
import type { SpecEntry } from "./entry.ts";
import type { SpecTarget } from "./targets.ts";

import {
  applyOverlays,
  loadJsonPath,
  serializeDocument,
} from "../../spec/index.ts";
import { errorText } from "../core/errors.ts";
import { VERSION } from "../version.ts";
import { readCachedRender, sha256, writeCachedRender } from "./cache.ts";
import { documentFormatId } from "./entry.ts";
import { documentText, fieldOf, parseAs, parseDocumentText } from "./text.ts";

/** A rendered target: its text and every finding. */
export interface RenderedTarget {
  readonly target: SpecTarget;
  readonly pin: string;
  readonly text: string;
  readonly diagnostics: readonly SpecDiagnostic[];
  readonly cached: boolean;
}

export interface RenderContext {
  readonly root: string;
  readonly entry: SpecEntry;
  /** Read and write the render cache. */
  readonly cache: boolean;
  /** Also check the document against the format's official JSON Schema. */
  readonly validate: boolean;
}

interface LoadedOverlays {
  readonly texts: readonly string[];
  readonly overlays: readonly Overlay[];
  readonly diagnostics: readonly SpecDiagnostic[];
}

const isOverlay = (value: unknown): value is Overlay =>
  typeof value === "object" &&
  value !== null &&
  "overlay" in value &&
  typeof value.overlay === "string" &&
  "actions" in value &&
  Array.isArray(value.actions);

async function loadOverlays(
  root: string,
  paths: readonly string[],
): Promise<LoadedOverlays> {
  const texts: string[] = [];
  const overlays: Overlay[] = [];
  const diagnostics: SpecDiagnostic[] = [];

  for (const path of paths) {
    const text = await readFile(resolve(root, path), "utf-8");
    texts.push(text);
    let parsed: unknown;

    try {
      parsed = parseDocumentText(path, text);
    } catch (error) {
      diagnostics.push({
        code: "overlay-invalid",
        severity: "error",
        message: `${path} does not parse: ${errorText(error)}`,
      });
      continue;
    }

    if (isOverlay(parsed)) {
      overlays.push(parsed);
    } else {
      diagnostics.push({
        code: "overlay-invalid",
        severity: "error",
        message: `${path} is not an Overlay document (it needs \`overlay\` and \`actions\`).`,
      });
    }
  }

  return { texts, overlays, diagnostics };
}

let jsonpath: Promise<JsonPathEngine> | undefined;

/**
 * The JSONPath engine, inlined into the CLI build and loaded only when an
 * output has overlays.
 */
function jsonPathEngine(): Promise<JsonPathEngine> {
  jsonpath ??= loadJsonPath(() => import("jsonpath-rfc9535"));

  return jsonpath;
}

const overlayEngine =
  (engine: JsonPathEngine): OverlayEngine =>
  (document, overlays) =>
    applyOverlays(document, overlays.filter(isOverlay), { jsonpath: engine });

/**
 * The model (or document) as canonical JSON, or undefined when it can't be
 * serialized.
 */
function sourceFingerprint(
  target: SpecTarget,
  entry: SpecEntry,
): string | undefined {
  const source: unknown = entry.api
    ? entry.api.model
    : entry.documents.get(target.format.id);

  try {
    return sha256(serializeDocument(source, { indent: 0, sortKeys: true }));
  } catch {
    return undefined;
  }
}

function renderDocument(
  target: SpecTarget,
  entry: SpecEntry,
  overlays: readonly Overlay[],
  engine: JsonPathEngine | undefined,
): { document: unknown; diagnostics: readonly SpecDiagnostic[] } {
  const applyEngine = engine ? overlayEngine(engine) : undefined;

  if (entry.api) {
    const result = entry.api.render(target.format, {
      version: target.version,
      ...(overlays.length > 0 ? { overlays } : {}),
      ...(applyEngine ? { applyOverlays: applyEngine } : {}),
    });

    return { document: result.document, diagnostics: result.diagnostics };
  }

  const document = entry.documents.get(target.format.id);
  const diagnostics: SpecDiagnostic[] = [];
  const declared = fieldOf(document, documentFormatId(document) ?? "");

  if (typeof declared === "string" && !declared.startsWith(target.version)) {
    diagnostics.push({
      code: "document-version",
      severity: "error",
      message: `The entry exports ${target.format.id} ${declared}, not ${target.version}. Export \`api\` (defineApi) to render any version.`,
    });
  }

  const overlaid =
    applyEngine && overlays.length > 0
      ? applyEngine(document, overlays)
      : { document };

  diagnostics.push(...(overlaid.diagnostics ?? []));

  try {
    diagnostics.push(
      ...(target.format.lint?.(overlaid.document, target.version) ?? []),
    );
  } catch (cause) {
    // A hand-written document can miss parts a format's lint expects.
    diagnostics.push({
      code: "lint-failed",
      severity: "warning",
      message: `The ${target.format.id} lint stopped: ${errorText(cause)}`,
    });
  }

  return { document: overlaid.document, diagnostics };
}

/**
 * Renders one target, or reads it from the cache when the model, the overlays,
 * the format version and the CLI version all match.
 */
export async function renderTarget(
  target: SpecTarget,
  context: RenderContext,
): Promise<RenderedTarget> {
  const pin: string =
    target.format.versions[target.version]?.pin ?? target.version;

  const loaded = await loadOverlays(context.root, target.overlays);

  const fingerprint = context.cache
    ? sourceFingerprint(target, context.entry)
    : undefined;

  const key =
    fingerprint === undefined
      ? undefined
      : sha256(
          JSON.stringify([
            VERSION,
            target.format.id,
            target.version,
            pin,
            target.serialization,
            fingerprint,
            loaded.texts,
            context.entry.cacheKey ?? null,
          ]),
        );

  const hit = key
    ? await readCachedRender(context.root, target.output, key)
    : undefined;

  if (hit && (!context.validate || hit.schema)) {
    return {
      target,
      pin,
      text: hit.text,
      diagnostics: [
        ...hit.diagnostics,
        ...(context.validate ? (hit.schema ?? []) : []),
      ],
      cached: true,
    };
  }

  let text: string;
  let diagnostics: readonly SpecDiagnostic[];
  let rendered: unknown;

  if (hit) {
    text = hit.text;
    diagnostics = hit.diagnostics;
    rendered = parseAs(target.serialization, text);
  } else {
    const engine =
      loaded.overlays.length > 0 ? await jsonPathEngine() : undefined;

    const result = renderDocument(
      target,
      context.entry,
      loaded.overlays,
      engine,
    );

    rendered = result.document;
    text = documentText(result.document, target.serialization);
    diagnostics = [...loaded.diagnostics, ...result.diagnostics];
  }

  let schema: readonly SpecDiagnostic[] | undefined;

  if (context.validate) {
    // Ajv and the official schemas load only for `validate`.
    const { validateDocument } = await import("./validate.ts");
    schema = await validateDocument(target.format.id, target.version, rendered);
  }

  if (key) {
    await writeCachedRender(context.root, target.output, {
      key,
      text,
      diagnostics,
      ...(schema ? { schema } : {}),
    });
  }

  return {
    target,
    pin,
    text,
    diagnostics: [...diagnostics, ...(schema ?? [])],
    cached: false,
  };
}
