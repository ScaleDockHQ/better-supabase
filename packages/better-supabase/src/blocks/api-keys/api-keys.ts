import type { JWTClaims } from "@supabase/server";

import type { AuthResolver, ResolvedState } from "../../auth/resolve.ts";
import type { BlockTransport } from "../../core/block-transport.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  instantArg,
  optionalInstant,
  optionalText,
  randomToken,
  recordOf,
  recordsOf,
  sha256Hex,
  stringsOf,
  textOf,
} from "../shared.ts";

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

export interface ApiKeysOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /** The token's first segment, lowercase letters and digits. Defaults to `bs`. */
  readonly prefix?: string;
}

export interface ParsedApiKey {
  readonly prefix: string;
  readonly publicId: string;
  readonly secret: string;
}

const TOKEN = /^([a-z][a-z0-9]*)_([0-9a-f]{16})_([A-Za-z0-9_-]{32,})$/;
const PREFIX = /^[a-z][a-z0-9]*$/;

/** Splits `<prefix>_<public id>_<secret>`, or `undefined` for anything else (a JWT, say). */
export function parseApiKey(token: string): ParsedApiKey | undefined {
  const match = TOKEN.exec(token.trim());
  if (!match) return undefined;
  return { prefix: match[1]!, publicId: match[2]!, secret: match[3]! };
}

function publicId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
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
    createdAt: optionalInstant(row["created_at"]) ?? Temporal.Now.instant(),
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
    const secret = randomToken(32);
    return {
      id,
      token: `${prefix}_${id}_${secret}`,
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
              rotateOptions.grace ?? Temporal.Duration.from({ days: 1 })
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

export interface ApiKeyResolverOptions {
  /** `createApiKeys` over a service transport. */
  readonly keys: Pick<ApiKeys, "verify">;
  /** The header that carries the key besides `Authorization: Bearer`. Defaults to `x-api-key`. */
  readonly header?: string;
}

/** The claims queries run with for a key. */
export function apiKeyClaims(key: ApiKey): JWTClaims {
  return {
    sub: key.userId ?? "",
    role: "authenticated",
    aud: "authenticated",
    api_key: {
      id: key.id,
      name: key.name,
      scopes: key.scopes,
      ...(key.organizationId ? { organization_id: key.organizationId } : {}),
    },
  };
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
            claims: apiKeyClaims(key),
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
