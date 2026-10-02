const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** Standard base64 (RFC 4648 section 4) of `input`, with padding. */
export function toBase64(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? encoder.encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** Bytes of standard or URL-safe base64, padded or not. Throws on invalid input. */
export function fromBase64(text: string): Uint8Array<ArrayBuffer> {
  const base64 = text.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

/** URL-safe base64 (RFC 4648 section 5) of `input`, without padding. */
export function toBase64Url(input: Uint8Array | string): string {
  return toBase64(input)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

/** UTF-8 text of base64 or base64url. Throws on invalid input. */
export function base64ToText(text: string): string {
  return decoder.decode(fromBase64(text));
}

/**
 * The payload of a JWT, decoded without verifying the signature. Only for
 * reading claims such as `exp` from a token that is verified elsewhere.
 */
export function decodeJwtPayload(
  token: string,
): Record<string, unknown> | undefined {
  const part = token.split(".")[1];
  if (!part) return undefined;
  try {
    const parsed: unknown = JSON.parse(base64ToText(part));
    // SAFETY: parsed is a non-null object, and callers check each claim they read.
    return typeof parsed === "object" && parsed !== null
      ? (parsed as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}
