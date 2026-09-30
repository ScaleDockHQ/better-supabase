const encoder = new TextEncoder();
const decoder = new TextDecoder();

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function fromBase64Url(text: string): Uint8Array {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

/** Opaque, URL-safe keyset cursor. */
export function encodeCursor(values: readonly unknown[]): string {
  return toBase64Url(encoder.encode(JSON.stringify(values)));
}

export function decodeCursor(cursor: string): unknown[] | undefined {
  try {
    const parsed: unknown = JSON.parse(decoder.decode(fromBase64Url(cursor)));
    return Array.isArray(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}
