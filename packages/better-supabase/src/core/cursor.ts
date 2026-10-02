import { base64ToText, toBase64Url } from "./base64.ts";

/** Opaque, URL-safe keyset cursor. */
export function encodeCursor(values: readonly unknown[]): string {
  return toBase64Url(JSON.stringify(values));
}

export function decodeCursor(cursor: string): unknown[] | undefined {
  try {
    const parsed: unknown = JSON.parse(base64ToText(cursor));
    return Array.isArray(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}
