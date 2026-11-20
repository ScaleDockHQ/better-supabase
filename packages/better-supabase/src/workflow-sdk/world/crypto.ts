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

/** One master key of a key ring. */
export interface RingKey {
  /** Names the key in logs and docs; never stored with run data. */
  readonly id: string;
  readonly key: Uint8Array;
  /** Runs created at or after this time use the key; the first entry's is 0. */
  readonly from: number;
}

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * The creation time of a run, from the ULID in its id (`wrun_<ULID>`), or
 * `undefined` for an id that doesn't carry one.
 */
export function runCreatedAt(runId: string): number | undefined {
  const ulid = runId.slice(runId.lastIndexOf("_") + 1).toUpperCase();

  if (ulid.length < 10) {
    return undefined;
  }

  let time = 0;

  for (const char of ulid.slice(0, 10)) {
    const value = CROCKFORD.indexOf(char);

    if (value === -1) {
      return undefined;
    }

    time = time * 32 + value;
  }

  return time;
}

/**
 * A key ring from JSON: `[{ "id": "2026-q4", "key": "<base64 or hex>", "from":
 * "2026-10-01T00:00:00Z" }]`. The first entry applies to every run before the
 * second one's `from`, and so on, so rotating means appending a key with a
 * `from` in the future; no run ever changes key.
 */
export function parseKeyRing(text: string): RingKey[] {
  let parsed: unknown;

  try {
    parsed = JSON.parse(text);
  } catch {
    throw new TypeError(
      "better-supabase: the workflow encryption key ring must be a JSON array",
    );
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new TypeError(
      "better-supabase: the workflow encryption key ring must be a non-empty JSON array",
    );
  }

  const ring = parsed.map((entry: unknown, index): RingKey => {
    const record: Record<string, unknown> =
      typeof entry === "object" && entry !== null ? { ...entry } : {};

    const { id, key, from } = record;

    if (typeof id !== "string" || typeof key !== "string") {
      throw new TypeError(
        `better-supabase: key ring entry ${String(index)} needs a string id and key`,
      );
    }

    const time =
      index === 0 || from === undefined ? 0 : Date.parse(String(from));

    if (Number.isNaN(time)) {
      throw new TypeError(
        `better-supabase: key ring entry "${id}" has an invalid from date`,
      );
    }

    return { id, key: parseMasterKey(key), from: time };
  });

  for (const [index, entry] of ring.entries()) {
    const previous = ring[index - 1];

    if (previous !== undefined && entry.from <= previous.from) {
      throw new TypeError(
        `better-supabase: key ring entry "${entry.id}" must start after the one before it`,
      );
    }
  }

  return ring;
}

/**
 * The ring key a run uses: the latest one that started at or before the run's
 * creation. A run id without a time gets the newest key.
 */
export function ringKeyFor(ring: readonly RingKey[], runId: string): RingKey {
  const created = runCreatedAt(runId);
  const newest = ring.at(-1);

  if (newest === undefined) {
    throw new TypeError("better-supabase: the key ring is empty");
  }

  if (created === undefined) {
    return newest;
  }

  let found = ring[0] ?? newest;

  for (const entry of ring) {
    if (entry.from <= created) {
      found = entry;
    }
  }

  return found;
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
