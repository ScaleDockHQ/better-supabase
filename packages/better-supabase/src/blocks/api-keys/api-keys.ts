import type { JWTClaims } from "@supabase/server";

import type { AuthResolver, ResolvedState } from "../../auth/resolve.ts";
import type { BlockTransport } from "../../core/block-transport.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  sha256Hex,
  stringsOf,
  textOf,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

export type ApiKeyState = "active" | "grace" | "revoked" | "expired";

export interface ApiKey {
  readonly id: string;
  /** Set for a tenant key, and for a personal key limited to one tenant. */
  readonly organizationId?: string;
  /** Set for a personal key: it acts as this user. */
  readonly userId?: string;
  readonly name: string;
  readonly prefix: string;
  readonly publicId: string;
  readonly scopes: readonly string[];
  /** Requests per minute, when the key has a limit. */
  readonly rateLimit?: number;
  readonly expiresAt?: Temporal.Instant;
  readonly lastUsedAt?: Temporal.Instant;
  /** In the future while a rotated key's grace period runs. */
  readonly revokedAt?: Temporal.Instant;
  readonly rotatedFrom?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly state: ApiKeyState;
  readonly successorId?: string;
}

/** A new key. `token` is shown once: only its hash is stored. */
export interface CreatedApiKey {
  readonly key: ApiKey;
  readonly token: string;
}

export interface CreateApiKeyInput {
  readonly name: string;
  /** The tenant the key acts in. Required unless `personal`. */
  readonly organizationId?: string;
  /** Acts as the signed-in user (in `organizationId` only, when set). */
  readonly personal?: boolean;
  /** `*` grants every scope. */
  readonly scopes?: readonly string[];
  readonly expiresAt?: Temporal.Instant;
  /** Requests per minute. */
  readonly rateLimit?: number;
}

export type ApiKeyCheck =
  | { readonly status: "ok"; readonly key: ApiKey }
  | { readonly status: "invalid" }
  | { readonly status: "rate_limited"; readonly retryAfter: number };

export interface ApiKeys {
  create(input: CreateApiKeyInput): AsyncResult<CreatedApiKey>;
  /** A tenant's keys for its managers (the caller's own otherwise), or the caller's personal keys. */
  list(organizationId?: string): AsyncResult<readonly ApiKey[]>;
  revoke(id: string): AsyncResult<boolean>;
  /** A new token for the key; the old one keeps working for `grace` (one day by default). */
  rotate(
    id: string,
    options?: { readonly grace?: Temporal.Duration },
  ): AsyncResult<CreatedApiKey>;
  /** Checks a presented token and counts the request. Needs a service transport. */
  verify(token: string): AsyncResult<ApiKeyCheck>;
}

export interface ApiKeysOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /** The token's first segment, lowercase letters and digits. Defaults to `bs`. */
  readonly prefix?: string;
}

export interface ParsedApiKey {
  readonly prefix: string;
  readonly publicId: string;
  readonly secret: string;
  /** Whether the token ends in a checksum; keys created before it have none. */
  readonly checksum: boolean;
}

const TOKEN = /^([a-z][a-z0-9]*)_([0-9a-f]{16})_([A-Za-z0-9_-]{32,})$/;
const PREFIX = /^[a-z][a-z0-9]*$/;
const ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const SECRET_LENGTH = 43;
const CHECKSUM_LENGTH = 6;
const CHECKED_TAIL = /^[A-Za-z0-9]{49}$/;

const CRC_TABLE = ((): Uint32Array => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1)
      value = value & 1 ? 0xed_b8_83_20 ^ (value >>> 1) : value >>> 1;
    table[index] = value >>> 0;
  }
  return table;
})();

/**
 * The CRC-32 (IEEE 802.3) of `text` as 6 base62 characters: the checksum
 * GitHub-style tokens end in, so a secret
 * scanner or the server rejects a mistyped key without a lookup.
 */
export function apiKeyChecksum(text: string): string {
  let crc = 0xff_ff_ff_ff;
  for (let index = 0; index < text.length; index += 1)
    crc =
      (CRC_TABLE[(crc ^ (text.codePointAt(index) ?? 0)) & 0xff] ?? 0) ^
      (crc >>> 8);
  let value = (crc ^ 0xff_ff_ff_ff) >>> 0;
  let out = "";
  for (let index = 0; index < CHECKSUM_LENGTH; index += 1) {
    out = ALPHABET[value % 62]! + out;
    value = Math.floor(value / 62);
  }
  return out;
}

function base62Secret(): string {
  let secret = "";
  const bytes = new Uint8Array(64);
  while (secret.length < SECRET_LENGTH) {
    crypto.getRandomValues(bytes);
    for (const byte of bytes) {
      // 248 = 4 * 62: rejecting the rest keeps every character equally likely.
      if (byte < 248 && secret.length < SECRET_LENGTH)
        secret += ALPHABET[byte % 62];
    }
  }
  return secret;
}

/**
 * Splits `<prefix>_<public id>_<secret><checksum>`: a 43-character base62
 * secret and the 6-character checksum of everything before it. A key from
 * before the checksum (`<prefix>_<public id>_<secret>`) still parses. A
 * checksum that doesn't match, or anything else (a JWT, say), is
 * `undefined`.
 */
export function parseApiKey(token: string): ParsedApiKey | undefined {
  const match = TOKEN.exec(token.trim());
  if (!match) return undefined;
  const prefix = match[1]!;
  const publicId = match[2]!;
  const tail = match[3]!;
  if (CHECKED_TAIL.test(tail)) {
    const secret = tail.slice(0, SECRET_LENGTH);
    return tail.slice(SECRET_LENGTH) ===
      apiKeyChecksum(`${prefix}_${publicId}_${secret}`)
      ? { prefix, publicId, secret, checksum: true }
      : undefined;
  }
  return { prefix, publicId, secret: tail, checksum: false };
}

function publicId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

const STATES: readonly ApiKeyState[] = [
  "active",
  "grace",
  "revoked",
  "expired",
];

function stateOf(
  value: unknown,
  revokedAt: Temporal.Instant | undefined,
  expiresAt: Temporal.Instant | undefined,
): ApiKeyState {
  const known = STATES.find((state) => state === value);
  if (known) return known;
  const now = temporal().Now.instant();
  const past = (at: Temporal.Instant | undefined): boolean =>
    at !== undefined && temporal().Instant.compare(at, now) <= 0;
  if (past(revokedAt)) return "revoked";
  if (past(expiresAt)) return "expired";
  return revokedAt === undefined ? "active" : "grace";
}

function apiKeyOf(value: unknown): ApiKey {
  const row = recordOf(value, "api key");
  const organizationId = optionalText(row["organization_id"]);
  const userId = optionalText(row["user_id"]);
  const expiresAt = optionalInstant(row["expires_at"]);
  const lastUsedAt = optionalInstant(row["last_used_at"]);
  const revokedAt = optionalInstant(row["revoked_at"]);
  const rotatedFrom = optionalText(row["rotated_from"]);
  const createdBy = optionalText(row["created_by"]);
  const successorId = optionalText(row["successor_id"]);
  const rateLimit = row["rate_limit"];
  return {
    id: textOf(row["id"]),
    ...(organizationId ? { organizationId } : {}),
    ...(userId ? { userId } : {}),
    name: textOf(row["name"]),
    prefix: textOf(row["prefix"]),
    publicId: textOf(row["public_id"]),
    scopes: stringsOf(row["scopes"]),
    ...(typeof rateLimit === "number" ? { rateLimit } : {}),
    ...(expiresAt ? { expiresAt } : {}),
    ...(lastUsedAt ? { lastUsedAt } : {}),
    ...(revokedAt ? { revokedAt } : {}),
    ...(rotatedFrom ? { rotatedFrom } : {}),
    ...(createdBy ? { createdBy } : {}),
    createdAt: optionalInstant(row["created_at"]) ?? temporal().Now.instant(),
    state: stateOf(row["state"], revokedAt, expiresAt),
    ...(successorId ? { successorId } : {}),
  };
}

function checkOf(value: unknown): ApiKeyCheck {
  const row = recordOf(value, "verify_api_key");
  switch (row["status"]) {
    case "ok":
      return { status: "ok", key: apiKeyOf(row["key"]) };
    case "rate_limited":
      return {
        status: "rate_limited",
        retryAfter: Number(row["retry_after"] ?? 60),
      };
    default:
      return { status: "invalid" };
  }
}

/**
 * API keys over the `api-keys` SQL module. Members create and rotate keys
 * with their own transport; `verify` (and `apiKeyResolver`) need one that
 * runs as the service role.
 */
export function createApiKeys(options: ApiKeysOptions): ApiKeys {
  applyTemporal(options);
  const prefix = options.prefix ?? "bs";
  if (!PREFIX.test(prefix)) {
    throw new TypeError(
      `createApiKeys: prefix must be lowercase letters and digits, not "${prefix}"`,
    );
  }
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
  );
  const fresh = async () => {
    const id = publicId();
    const secret = base62Secret();
    const key = `${prefix}_${id}_${secret}`;
    return {
      id,
      token: `${key}${apiKeyChecksum(key)}`,
      hash: await sha256Hex(secret),
    };
  };
  return {
    create: (input) =>
      AsyncResult.from(async () => {
        const { id, token, hash } = await fresh();
        return call(
          "create_api_key",
          {
            name: input.name,
            public_id: id,
            secret_hash: hash,
            tenant: input.organizationId ?? null,
            personal: input.personal ?? false,
            scopes: input.scopes ?? [],
            expires_at: instantArg(input.expiresAt) ?? null,
            rate_limit: input.rateLimit ?? null,
            prefix,
          },
          (value) => ({ key: apiKeyOf(value), token }),
        );
      }),
    list: (organizationId) =>
      call("list_api_keys", { tenant: organizationId ?? null }, (value) =>
        recordsOf(value, "list_api_keys").map(apiKeyOf),
      ),
    revoke: (id) =>
      call("revoke_api_key", { key: id }, (value) => value === true),
    rotate: (id, rotateOptions = {}) =>
      AsyncResult.from(async () => {
        const { id: next, token, hash } = await fresh();
        return call(
          "rotate_api_key",
          {
            key: id,
            public_id: next,
            secret_hash: hash,
            grace: (
              rotateOptions.grace ?? temporal().Duration.from({ days: 1 })
            ).toString(),
          },
          (value) => ({ key: apiKeyOf(value), token }),
        );
      }),
    verify: (token) =>
      AsyncResult.from(async () => {
        const parsed = parseApiKey(token);
        if (!parsed || parsed.prefix !== prefix)
          return ok<ApiKeyCheck>({ status: "invalid" });
        return call(
          "verify_api_key",
          {
            public_id: parsed.publicId,
            secret_hash: await sha256Hex(parsed.secret),
          },
          checkOf,
        );
      }),
  };
}

/**
 * A second claim for an authorization provider's SQL functions, with the
 * field names they read. Every field but `name` is optional.
 */
export interface ApiKeyExtraClaim {
  /** The claim. `api_key` adds the fields to the module's own claim. */
  readonly name: string;
  /** The field with the permission keys, default `scopes`. */
  readonly scopes?: string;
  /** The field with a tenant key's tenant, default `tenant`. */
  readonly tenant?: string;
  /** The field with a tenant key's roles, default `roles`. */
  readonly roles?: string;
  /** The roles a tenant key holds in its tenant, unless `serviceRoles` in the options answers. */
  readonly serviceRoles?: readonly string[];
}

export interface ApiKeyClaimsOptions {
  /**
   * Also write the claim an authorization provider's SQL functions read:
   * the scopes as a ceiling, and a tenant key's tenant and roles.
   */
  readonly claim?: ApiKeyExtraClaim;
  /** The roles a tenant key holds in its tenant; default `claim.serviceRoles`. */
  readonly serviceRoles?: (key: ApiKey) => readonly string[];
  /**
   * The permission keys `*` stands for in `claim`, which has no wildcard,
   * so without this a key with `*` allows nothing there.
   */
  readonly allPermissions?: readonly string[];
  /**
   * The claim that narrows a provider's functions to one tenant (such as
   * `tenant_id`), set for a personal key limited to a tenant.
   */
  readonly tenantClaim?: string;
}

export interface ApiKeyResolverOptions extends ApiKeyClaimsOptions {
  /** `createApiKeys` over a service transport. */
  readonly keys: Pick<ApiKeys, "verify">;
  /** The header that carries the key besides `Authorization: Bearer`. Defaults to `x-api-key`. */
  readonly header?: string;
}

/**
 * The claims queries run with for a key: `api_key` with `id`, `name`,
 * `scopes` and `organization_id` for the module's `has_scope()` and
 * `api_key_tenant()`, plus `options.claim`.
 */
export function apiKeyClaims(
  key: ApiKey,
  options: ApiKeyClaimsOptions = {},
): JWTClaims {
  const scopes =
    key.scopes.includes("*") && options.allPermissions
      ? [
          ...new Set([
            ...key.scopes.filter((scope) => scope !== "*"),
            ...options.allPermissions,
          ]),
        ]
      : key.scopes;
  const base: Record<string, unknown> = {
    id: key.id,
    name: key.name,
    scopes,
    ...(key.organizationId ? { organization_id: key.organizationId } : {}),
  };
  const claims: Record<string, unknown> = {
    sub: key.userId ?? "",
    role: "authenticated",
    aud: "authenticated",
    api_key: base,
  };
  if (options.claim !== undefined) {
    const names = options.claim;
    const claim = names.name;
    const service =
      key.userId === undefined && key.organizationId !== undefined;
    const roles = service
      ? (options.serviceRoles?.(key) ?? names.serviceRoles)
      : undefined;
    const target: Record<string, unknown> =
      claim === "api_key" ? base : { id: key.id, name: key.name };
    target[names.scopes ?? "scopes"] = scopes.filter((scope) => scope !== "*");
    if (service) target[names.tenant ?? "tenant"] = key.organizationId;
    if (roles && roles.length > 0) target[names.roles ?? "roles"] = [...roles];
    claims[claim] = target;
  }
  if (
    options.tenantClaim !== undefined &&
    key.userId !== undefined &&
    key.organizationId !== undefined
  ) {
    claims[options.tenantClaim] = key.organizationId;
  }
  // SAFETY: sub, role and aud are the JWTClaims fields; the rest are extra claims.
  return claims as JWTClaims;
}

function presented(request: Request, header: string): string | undefined {
  const direct = request.headers.get(header)?.trim();
  if (direct) return direct;
  const authorization = request.headers.get("authorization");
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  return bearer && parseApiKey(bearer) ? bearer : undefined;
}

/**
 * Resolves `x-api-key` (or a Bearer token shaped like a key) to an `apiKey`
 * auth state. Requests without one fall through to the JWT and cookie
 * resolution. Pass it to `createServer({ auth: { resolvers: [...] } })`.
 */
export function apiKeyResolver(options: ApiKeyResolverOptions): AuthResolver {
  const header = options.header ?? "x-api-key";
  return {
    name: "api-keys",
    async resolve(request): Promise<ResolvedState | undefined> {
      const token = presented(request, header);
      if (token === undefined) return undefined;
      const checked = await options.keys.verify(token);
      if (!checked.ok) return { kind: "invalid", error: checked.error };
      const check = checked.data;
      switch (check.status) {
        case "ok": {
          const { key } = check;
          return {
            kind: "apiKey",
            keyId: key.id,
            name: key.name,
            ...(key.organizationId
              ? { organizationId: key.organizationId }
              : {}),
            ...(key.userId ? { userId: key.userId } : {}),
            scopes: key.scopes,
            createdAt: key.createdAt,
            ...(key.createdBy ? { createdBy: key.createdBy } : {}),
            claims: apiKeyClaims(key, options),
          };
        }
        case "rate_limited":
          return {
            kind: "invalid",
            error: dbError("rate_limited", "API key rate limit exceeded", {
              code: "API_KEY_RATE_LIMITED",
              retryAfter: check.retryAfter,
            }),
          };
        case "invalid":
          return {
            kind: "invalid",
            error: dbError("unauthorized", "Invalid API key", {
              code: "INVALID_API_KEY",
            }),
          };
        default: {
          const exhaustive: never = check;
          return exhaustive;
        }
      }
    },
  };
}
