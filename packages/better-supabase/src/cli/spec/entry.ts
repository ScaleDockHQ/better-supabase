import { existsSync } from "node:fs";

import type {
  AnyDocumentFormat,
  ApiModel,
  RenderOptions,
  RenderResult,
} from "../../spec/index.ts";

import { CliError } from "../core/errors.ts";
import { importFresh } from "../fresh-import.ts";
import { isRecord } from "../guards.ts";
import { isDocumentFormat } from "./formats.ts";

/** The part of `Api` (from `defineApi`) that `spec` uses. */
export interface ApiLike {
  readonly model: ApiModel;
  render<F extends AnyDocumentFormat>(
    format: F,
    options?: RenderOptions<F>,
  ): RenderResult<F>;
}

/** What a spec entry module provides. */
export interface SpecEntry {
  /** The `defineApi()` result: every format and version renders from it. */
  readonly api?: ApiLike;
  /** Finished documents by format id, for entries that export one document. */
  readonly documents: ReadonlyMap<string, unknown>;
  /** Formats beyond the built-in ones (`export const formats = [...]`). */
  readonly formats: readonly AnyDocumentFormat[];
  /** Folded into the cache key, for inputs the model doesn't show. */
  readonly cacheKey?: string;
}

const DOCUMENT_KEYS = ["openapi", "asyncapi", "arazzo"] as const;

function isApi(value: unknown): value is ApiLike {
  return (
    isRecord(value) &&
    isRecord(value["model"]) &&
    typeof value["render"] === "function"
  );
}

/**
 * The format id of a finished document (`{ openapi: "3.1.0", ... }` is
 * `openapi`).
 */
export function documentFormatId(value: unknown): string | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return DOCUMENT_KEYS.find((key) => typeof value[key] === "string");
}

async function settle(value: unknown): Promise<unknown> {
  if (typeof value !== "function") {
    return value;
  }

  // SAFETY: an exported function takes no arguments and returns the value.
  const result: unknown = await (value as () => unknown)();

  return result;
}

/**
 * Loads the entry module fresh (so `--watch` sees edits). It exports `api` (a
 * `defineApi()` result) or a document as `openapi`, `asyncapi`, `arazzo` or
 * default; each may be a function returning one. `formats` adds document
 * formats and `cacheKey` adds to the cache key.
 */
export async function loadSpecEntry(path: string): Promise<SpecEntry> {
  if (!existsSync(path)) {
    throw new CliError("not_found", `Module not found: ${path}`);
  }

  const loaded = await importFresh(path);
  const formats: AnyDocumentFormat[] = [];
  const exportedFormats = await settle(loaded["formats"]);

  if (Array.isArray(exportedFormats)) {
    for (const format of exportedFormats) {
      if (isDocumentFormat(format)) {
        formats.push(format);
      }
    }
  }

  const cacheKey =
    typeof loaded["cacheKey"] === "string" ? loaded["cacheKey"] : undefined;

  const base = { formats, ...(cacheKey === undefined ? {} : { cacheKey }) };

  const api = await settle(loaded["api"] ?? loaded["default"]);

  if (isApi(api)) {
    return { ...base, api, documents: new Map() };
  }

  const documents = new Map<string, unknown>();

  for (const key of DOCUMENT_KEYS) {
    const document = await settle(loaded[key]);

    if (documentFormatId(document) === key) {
      documents.set(key, document);
    }
  }

  const fallback = documentFormatId(api);

  if (fallback && !documents.has(fallback)) {
    documents.set(fallback, api);
  }

  return { ...base, documents };
}
