import type { AnyDocumentFormat } from "../../spec/index.ts";

import {
  arazzoFormat,
  asyncapiFormat,
  openapiFormat,
} from "../../spec/index.ts";
import { isRecord } from "../guards.ts";

/**
 * The first-party document formats `spec` knows by id. Entries add more through
 * a `formats` export, for example `createArazzoFormat()` with other source
 * description URLs.
 */
const BUILTIN_FORMATS: readonly AnyDocumentFormat[] = [
  openapiFormat,
  asyncapiFormat,
  arazzoFormat,
];

/** A value that implements `DocumentFormat` API v1. */
export function isDocumentFormat(value: unknown): value is AnyDocumentFormat {
  return (
    isRecord(value) &&
    value["apiVersion"] === 1 &&
    typeof value["id"] === "string" &&
    isRecord(value["versions"]) &&
    typeof value["defaultVersion"] === "string" &&
    typeof value["lower"] === "function" &&
    typeof value["fileName"] === "function"
  );
}

/**
 * The built-in formats, then the entry's, keyed by id; a later one with the
 * same id wins.
 */
export function formatRegistry(
  extra: readonly AnyDocumentFormat[] = [],
): ReadonlyMap<string, AnyDocumentFormat> {
  const registry = new Map<string, AnyDocumentFormat>();

  for (const format of [...BUILTIN_FORMATS, ...extra]) {
    registry.set(format.id, format);
  }

  return registry;
}
