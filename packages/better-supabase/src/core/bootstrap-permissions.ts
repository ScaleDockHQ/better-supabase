import { fromBase64, toBase64Url } from "./base64.ts";
import { isRecord } from "./guards.ts";

/**
 * The permissions a provider returns in the bootstrap RPC (API version 1), as
 * lists of keys: `tenants` maps a tenant id to the keys the caller holds there,
 * `platform` the keys held platform-wide.
 */
export interface BootstrapPermissionsFull {
  readonly apiVersion: 1;
  readonly form?: "full";
  readonly tenants: Readonly<Record<string, readonly string[]>>;
  readonly platform?: readonly string[];
}

/**
 * The compact form: `keys` lists every key once, and each tenant (and
 * `platform`) is a bitset over that list in base64 or base64url. Bit `i` is bit
 * `i % 8` of byte `i / 8` (least significant first) and means `keys[i]` is
 * held. A key shared by many tenants costs one bit per tenant instead of its
 * name.
 */
export interface BootstrapPermissionsCompact {
  readonly apiVersion: 1;
  readonly form: "compact";
  readonly keys: readonly string[];
  readonly tenants: Readonly<Record<string, string>>;
  readonly platform?: string;
}

/** Either form, as the database returns it. */
export type BootstrapPermissionsWire =
  | BootstrapPermissionsFull
  | BootstrapPermissionsCompact;

/** The permissions of the caller, expanded: what a page reads. */
export interface BootstrapPermissions {
  readonly apiVersion: 1;
  readonly tenants: Readonly<Record<string, readonly string[]>>;
  readonly platform: readonly string[];
}

/** The apiVersion this better-supabase reads. */
export const BOOTSTRAP_PERMISSIONS_API_VERSION = 1;

function keyList(value: unknown): readonly string[] | undefined {
  return Array.isArray(value) &&
    value.every((entry): entry is string => typeof entry === "string")
    ? value
    : undefined;
}

function bitsetKeys(
  encoded: unknown,
  keys: readonly string[],
): readonly string[] | undefined {
  if (typeof encoded !== "string") {
    return undefined;
  }

  let bytes: Uint8Array;

  try {
    // Postgres encode() inserts a newline every 76 characters. Count those
    // toward the padding and the bitset fails closed past 456 keys.
    bytes = fromBase64(encoded.replaceAll(/\s+/g, ""));
  } catch {
    return undefined;
  }

  // A bit past the end of the key list means the two sides disagree.
  if (bytes.length > Math.ceil(keys.length / 8)) {
    return undefined;
  }

  const held: string[] = [];

  for (const [index, key] of keys.entries()) {
    const byte = bytes[Math.floor(index / 8)] ?? 0;

    if (Math.floor(byte / 2 ** (index % 8)) % 2 === 1) {
      held.push(key);
    }
  }

  // Bits beyond the last key are padding and must be zero.
  const used = keys.length % 8;
  const last = bytes.length === Math.ceil(keys.length / 8) ? bytes.at(-1) : 0;

  return used !== 0 && last !== undefined && last >= 2 ** used
    ? undefined
    : held;
}

/**
 * Reads what a provider returned. `undefined` for anything this version does
 * not understand (another `apiVersion`, a malformed list or bitset), so the
 * caller falls back to its authorizer instead of trusting a guess: the contract
 * fails closed.
 */
export function expandBootstrapPermissions(
  value: unknown,
): BootstrapPermissions | undefined {
  if (
    !isRecord(value) ||
    value["apiVersion"] !== BOOTSTRAP_PERMISSIONS_API_VERSION ||
    !isRecord(value["tenants"])
  ) {
    return undefined;
  }

  const form = value["form"] ?? "full";
  const tenants: Record<string, readonly string[]> = {};

  if (form === "full") {
    for (const [tenant, keys] of Object.entries(value["tenants"])) {
      const list = keyList(keys);

      if (!list) {
        return undefined;
      }

      tenants[tenant] = list;
    }

    const platform =
      value["platform"] === undefined ? [] : keyList(value["platform"]);

    return platform ? { apiVersion: 1, tenants, platform } : undefined;
  }

  if (form !== "compact") {
    return undefined;
  }

  const keys = keyList(value["keys"]);

  if (!keys) {
    return undefined;
  }

  for (const [tenant, encoded] of Object.entries(value["tenants"])) {
    const held = bitsetKeys(encoded, keys);

    if (!held) {
      return undefined;
    }

    tenants[tenant] = held;
  }

  const platform =
    value["platform"] === undefined ? [] : bitsetKeys(value["platform"], keys);

  return platform ? { apiVersion: 1, tenants, platform } : undefined;
}

/**
 * The compact form of `permissions`, with the keys sorted. For providers and
 * tests; the database side writes the same bytes in SQL.
 */
export function compactBootstrapPermissions(
  permissions: Pick<BootstrapPermissions, "tenants" | "platform">,
): BootstrapPermissionsCompact {
  const keys = [
    ...new Set([
      ...permissions.platform,
      ...Object.values(permissions.tenants).flat(),
    ]),
  ].toSorted();

  const index = new Map(keys.map((key, at) => [key, at]));

  const encode = (held: readonly string[]): string => {
    const bytes = new Uint8Array(Math.ceil(keys.length / 8));

    for (const key of new Set(held)) {
      const at = index.get(key) ?? 0;
      const slot = Math.floor(at / 8);

      bytes[slot] = (bytes[slot] ?? 0) + 2 ** (at % 8);
    }

    return toBase64Url(bytes);
  };

  return {
    apiVersion: 1,
    form: "compact",
    keys,
    tenants: Object.fromEntries(
      Object.entries(permissions.tenants).map(([tenant, held]) => [
        tenant,
        encode(held),
      ]),
    ),
    ...(permissions.platform.length > 0
      ? { platform: encode(permissions.platform) }
      : {}),
  };
}
