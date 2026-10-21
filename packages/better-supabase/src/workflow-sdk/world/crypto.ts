import { hmacHex, timingSafeEqual } from "../../core/hmac.ts";
import { env } from "./env.ts";
import { HKDF_SALT, SIGNATURE_TOLERANCE_SECONDS } from "./types.ts";

const encoder = /* @__PURE__ */ new TextEncoder();

/** A 32-byte key from base64 or hex. */
export function parseMasterKey(value: string): Uint8Array {
  const text = value.trim();

  const bytes = /^[0-9a-f]{64,}$/i.test(text)
    ? Buffer.from(text, "hex")
    : Buffer.from(text, "base64");

  if (bytes.byteLength < 32) {
    throw new TypeError(
      "better-supabase: the workflow encryption key must be at least 32 bytes, base64 or hex",
    );
  }

  return new Uint8Array(bytes);
}

/** The run's AES-256 key: HKDF-SHA256 of the master key with info `run:<runId>`. */
export async function deriveRunKey(
  master: Uint8Array,
  runId: string,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(master),
    "HKDF",
    false,
    ["deriveBits"],
  );

  const bits = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode(HKDF_SALT),
      info: encoder.encode(`run:${runId}`),
    },
    key,
    256,
  );

  return new Uint8Array(bits);
}

/** `t=<unix>,v1=<hex>` over `<t>.<job>.<body>`. */
export async function signDelivery(
  secret: string,
  job: string,
  body: string,
  now: number = Date.now(),
): Promise<string> {
  const t = String(Math.floor(now / 1000));

  return `t=${t},v1=${await hmacHex(secret, `${t}.${job}.${body}`)}`;
}

/**
 * Whether `header` signs `job` and `body` with `secret` within five minutes of
 * `now`.
 */
export async function verifyDelivery(
  secret: string,
  header: string | null,
  job: string,
  body: string,
  now: number = Date.now(),
): Promise<boolean> {
  if (header === null) {
    return false;
  }

  const parts = new Map(
    header.split(",").map((part) => {
      const index = part.indexOf("=");

      return [part.slice(0, index).trim(), part.slice(index + 1).trim()];
    }),
  );

  const t = parts.get("t");
  const v1 = parts.get("v1");

  if (t === undefined || v1 === undefined || !/^\d+$/.test(t)) {
    return false;
  }

  if (Math.abs(now / 1000 - Number(t)) > SIGNATURE_TOLERANCE_SECONDS) {
    return false;
  }

  return timingSafeEqual(await hmacHex(secret, `${t}.${job}.${body}`), v1);
}

/**
 * Unsigned poll deliveries are accepted only when `NODE_ENV` is `development`
 * or `test`.
 */
export function unsignedAllowed(): boolean {
  const mode = env("NODE_ENV");

  return mode === "development" || mode === "test";
}
