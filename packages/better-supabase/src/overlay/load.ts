import type { JsonPathEngine } from "./types.ts";

import { importOptionalPeer, memoized } from "../core/optional-peer.ts";

const isEngine = (value: unknown): value is JsonPathEngine =>
  typeof value === "object" &&
  value !== null &&
  "paths" in value &&
  typeof value.paths === "function";

/**
 * Imports `jsonpath-rfc9535` on first use. The specifier is a variable so
 * bundlers leave the optional peer out of apps that pass their own engine.
 */
const importEngine = (): Promise<unknown> =>
  importOptionalPeer("jsonpath-rfc9535");

async function load(importer: () => Promise<unknown>): Promise<JsonPathEngine> {
  const module = await importer();

  if (!isEngine(module)) {
    throw new TypeError(
      "Overlays need an RFC 9535 JSONPath engine: pnpm add jsonpath-rfc9535, or pass your own { paths(document, expression) }",
    );
  }

  return module;
}

const cachedEngine = memoized(() => load(importEngine));

/**
 * Loads the optional `jsonpath-rfc9535` peer, an RFC 9535 implementation that
 * passes the JSONPath Compliance Test Suite, for `applyOverlay`. Rejects with
 * an install message when the package is missing. The engine is loaded once per
 * module; `importer` replaces the import in tests.
 */
export function loadJsonPath(
  importer?: () => Promise<unknown>,
): Promise<JsonPathEngine> {
  if (importer) {
    return load(importer);
  }

  return cachedEngine();
}
