/* oxlint-disable eslint/no-bitwise -- the constant-time comparison ORs the XOR of every byte. */

// Dependency-free HMAC primitives: the workflow world bundle imports these without the webhook code.

let encoderInstance: InstanceType<typeof TextEncoder> | undefined;

// Created on first use: not every runtime has the global at import time.
export const encoder: Pick<InstanceType<typeof TextEncoder>, "encode"> = {
  encode: (text) => (encoderInstance ??= new TextEncoder()).encode(text),
};

/** Constant-time string comparison. */
export function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;

  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }

  return diff === 0;
}

/** Lowercase hex of a byte array. */
const toHex = (bytes: Uint8Array): string =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

/** The hex HMAC-SHA-256 of `message`, keyed with the UTF-8 bytes of `secret`. */
export async function hmacHex(
  secret: string,
  message: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  return toHex(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(message)),
    ),
  );
}
