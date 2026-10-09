import type { BlockTransport } from "../core/block-transport.ts";
import type { ErrorMapper } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
  CredentialToken,
  SetCredentialOptions,
} from "./provider.ts";

import {
  timingSafeEqual,
  verifySharedSecret,
  verifyWebhook,
} from "../blocks/webhooks/verify.ts";
import { blockCall, DEFAULT_BLOCK_SCHEMA } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

/** How a request the third party sends is signed with the stored secret. */
export type VaultInboundScheme =
  | "standard-webhooks"
  | "hmac-sha256"
  | "shared-secret";

/**
 * A credential in Vault. `scope: 'user'` keeps one secret per user subject.
 * The token goes out as `<header>: <scheme> <token>`, `Authorization: Bearer`
 * by default; `scheme: null` sends it bare (`x-api-key`).
 */
export interface VaultCredentialRef {
  readonly provider: "vault";
  readonly secret: string;
  /** Stores the secret as `tenant/<tenant>/<secret>`, apart from every other tenant's. */
  readonly tenant?: string;
  readonly scope?: "app" | "user";
  readonly header?: string;
  readonly scheme?: string | null;
  readonly inbound?: VaultInboundScheme;
  /** Defaults to `x-hub-signature-256` for `hmac-sha256`, `authorization` for `shared-secret`. */
  readonly signatureHeader?: string;
}

export interface VaultCredentialsOptions {
  /** `sqlTransport(postgres.asService())` or `rpcTransport` with the service role key. */
  readonly transport: BlockTransport;
  /** The schema of the `credentials` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * How long a read secret stays in memory, in milliseconds. Defaults to
   * 60000; `0` reads Vault on every call. `set` and `revoke` clear it.
   */
  readonly cacheMs?: number;
}

export interface VaultCredentials extends CredentialProvider {
  readonly name: "vault";
  /** Stores or replaces the credential a ref names, for `subject` when the ref is per user. */
  set(
    ref: CredentialRef,
    value: string,
    options?: SetCredentialOptions,
  ): AsyncResult<void>;
  verifyInbound(request: Request, ref: CredentialRef): AsyncResult<boolean>;
}

const MAX_CACHED = 256;

const invalidRef = (message: string): Result<never> =>
  err(dbError("invalid_input", message, { hint: "CREDENTIAL_REF_INVALID" }));

const TENANT = /^[A-Za-z0-9][A-Za-z0-9._:@-]{0,99}$/;
const TENANT_PREFIX = "tenant/";

function vaultRef(ref: CredentialRef): Result<VaultCredentialRef> {
  if (ref.provider !== "vault")
    return invalidRef(`vault does not resolve "${ref.provider}" credentials`);
  const { secret, tenant, scope, header, scheme, inbound, signatureHeader } =
    ref;
  if (typeof secret !== "string" || secret.length === 0)
    return invalidRef("a vault credential ref needs a secret name");
  if (tenant !== undefined) {
    if (typeof tenant !== "string" || !TENANT.test(tenant))
      return invalidRef(
        "tenant is an id of letters, digits and ._:@- without a slash",
      );
    if (secret.includes("/"))
      return invalidRef("a tenant's secret name has no slash");
  } else if (secret.startsWith(TENANT_PREFIX)) {
    return invalidRef(
      `a secret name starting with "${TENANT_PREFIX}" needs its tenant set`,
    );
  }
  if (scope !== undefined && scope !== "app" && scope !== "user")
    return invalidRef('scope is "app" or "user"');
  if (header !== undefined && typeof header !== "string")
    return invalidRef("header is a header name");
  if (scheme !== undefined && scheme !== null && typeof scheme !== "string")
    return invalidRef("scheme is a string or null");
  if (
    inbound !== undefined &&
    inbound !== "standard-webhooks" &&
    inbound !== "hmac-sha256" &&
    inbound !== "shared-secret"
  )
    return invalidRef(
      'inbound is "standard-webhooks", "hmac-sha256" or "shared-secret"',
    );
  if (signatureHeader !== undefined && typeof signatureHeader !== "string")
    return invalidRef("signatureHeader is a header name");
  return ok({
    provider: "vault",
    secret,
    ...(tenant === undefined ? {} : { tenant }),
    ...(scope === undefined ? {} : { scope }),
    ...(header === undefined ? {} : { header }),
    ...(scheme === undefined ? {} : { scheme }),
    ...(inbound === undefined ? {} : { inbound }),
    ...(signatureHeader === undefined ? {} : { signatureHeader }),
  });
}

/**
 * The Vault name under `bs:cred:vault:`: `tenant/<tenant>/<secret>` for a
 * tenant's ref; per-user secrets end in `@<user id>`.
 */
function storageName(
  ref: VaultCredentialRef,
  subject: CredentialSubject | undefined,
): Result<string> {
  const base =
    ref.tenant === undefined
      ? ref.secret
      : `${TENANT_PREFIX}${ref.tenant}/${ref.secret}`;
  if (ref.scope !== "user") return ok(base);
  if (subject?.type !== "user")
    return err(
      dbError("forbidden", `"${ref.secret}" is stored per user`, {
        hint: "CREDENTIAL_SUBJECT_REQUIRED",
      }),
    );
  return ok(`${base}@${subject.id}`);
}

function headersFor(
  ref: VaultCredentialRef,
  token: string,
): Record<string, string> {
  const scheme = ref.scheme === undefined ? "Bearer" : ref.scheme;
  return {
    [(ref.header ?? "authorization").toLowerCase()]:
      scheme === null ? token : `${scheme} ${token}`,
  };
}

const encoder = /* @__PURE__ */ new TextEncoder();

async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(body)),
  );
  return Array.from(signature, (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function verifyWith(
  ref: VaultCredentialRef,
  scheme: VaultInboundScheme,
  request: Request,
  secret: string,
): Promise<boolean> {
  switch (scheme) {
    case "standard-webhooks": {
      const verified = await verifyWebhook(
        { headers: request.headers, body: await request.text() },
        secret,
      );
      // A valid signature over a body that isn't JSON still proves the sender.
      return verified.ok || verified.error.kind === "invalid_request";
    }
    case "hmac-sha256": {
      const offered = (
        request.headers.get(ref.signatureHeader ?? "x-hub-signature-256") ?? ""
      ).replace(/^sha256=/i, "");
      return timingSafeEqual(
        offered.toLowerCase(),
        await hmacHex(secret, await request.text()),
      );
    }
    case "shared-secret": {
      return verifySharedSecret(
        request,
        secret,
        ref.signatureHeader ?? "authorization",
      );
    }
    default: {
      const unreachable: never = scheme;
      return unreachable;
    }
  }
}

/**
 * A `CredentialProvider` over the `credentials` SQL module: tokens and API
 * keys in Supabase Vault, read through security definer functions only the
 * service role may call. Static secrets only; OAuth connections come from
 * a provider such as `better-supabase/vercel-connect`.
 */
export function vaultCredentials(
  options: VaultCredentialsOptions,
): VaultCredentials {
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );
  const cacheMs = options.cacheMs ?? 60_000;
  const cache = new Map<string, { value: string; until: number }>();

  const read = (name: string): AsyncResult<string> => {
    const cached = cache.get(name);
    if (cached !== undefined && cached.until > Date.now())
      return AsyncResult.ok(cached.value);
    return call(
      "credential_get",
      { provider: "vault", name },
      (value) => value,
    ).andThen((value) => {
      if (typeof value !== "string")
        return Promise.resolve(
          err(
            dbError("not_found", `No credential is stored as "${name}"`, {
              hint: "CREDENTIAL_NOT_FOUND",
            }),
          ),
        );
      if (cacheMs > 0) {
        if (cache.size >= MAX_CACHED) cache.clear();
        cache.set(name, { value, until: Date.now() + cacheMs });
      }
      return Promise.resolve(ok(value));
    });
  };

  const resolve = (
    ref: CredentialRef,
    subject: CredentialSubject | undefined,
  ): Result<{ ref: VaultCredentialRef; name: string }> => {
    const parsed = vaultRef(ref);
    if (!parsed.ok) return parsed;
    const name = storageName(parsed.data, subject);
    return name.ok ? ok({ ref: parsed.data, name: name.data }) : name;
  };

  return {
    apiVersion: 1,
    name: "vault",
    getToken(ref, getOptions) {
      const resolved = resolve(ref, getOptions.subject);
      if (!resolved.ok) return AsyncResult.err(resolved.error);
      return read(resolved.data.name).map((token): CredentialToken => ({
        token,
        headers: headersFor(resolved.data.ref, token),
      }));
    },
    capabilities(ref) {
      const parsed = vaultRef(ref);
      return {
        userSubjects: parsed.ok && parsed.data.scope === "user",
        authorization: false,
        revoke: true,
        inbound: parsed.ok && parsed.data.inbound !== undefined,
      };
    },
    revoke(ref, revokeOptions) {
      const resolved = resolve(ref, revokeOptions.subject);
      if (!resolved.ok) return AsyncResult.err(resolved.error);
      const { name } = resolved.data;
      cache.delete(name);
      return call(
        "credential_delete",
        { provider: "vault", name },
        (value) => value === true,
      );
    },
    set(ref, value, setOptions = {}) {
      const resolved = resolve(ref, setOptions.subject);
      if (!resolved.ok) return AsyncResult.err(resolved.error);
      const { name } = resolved.data;
      cache.delete(name);
      return call(
        "credential_set",
        {
          provider: "vault",
          name,
          secret: value,
          description: setOptions.description ?? null,
        },
        () => {},
      );
    },
    verifyInbound(request, ref) {
      const parsed = vaultRef(ref);
      if (!parsed.ok) return AsyncResult.err(parsed.error);
      const { inbound } = parsed.data;
      if (inbound === undefined)
        return AsyncResult.err(
          dbError(
            "invalid_input",
            `"${parsed.data.secret}" has no inbound scheme`,
            {
              hint: "CREDENTIAL_REF_INVALID",
            },
          ),
        );
      const name = storageName(parsed.data, { type: "app" });
      if (!name.ok) return AsyncResult.err(name.error);
      return read(name.data).andThen(async (secret) =>
        ok(await verifyWith(parsed.data, inbound, request.clone(), secret)),
      );
    },
  };
}
