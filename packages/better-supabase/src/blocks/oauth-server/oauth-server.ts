import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";

import { toBase64Url } from "../../core/base64.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  enumOrThrow,
  instantOf,
  nullableInstant,
  nullableText,
  randomToken,
  recordOf,
  recordOrEmpty,
  recordsOf,
  run,
  sha256Hex,
  stringsOf,
  textOf,
} from "../shared.ts";

const AUTH_METHODS = [
  "none",
  "client_secret_basic",
  "client_secret_post",
] as const;

const GRANT_TYPES = [
  "authorization_code",
  "refresh_token",
  "client_credentials",
  "urn:ietf:params:oauth:grant-type:device_code",
] as const;

/** How a client authenticates at the token endpoint (RFC 7591 section 2). */
export type OAuthClientAuthMethod = (typeof AUTH_METHODS)[number];

/** A grant type a client may use. */
export type OAuthGrantType = (typeof GRANT_TYPES)[number];

export interface OAuthServerOptions extends BlockOptions {
  /** How long an authorization code is valid, in seconds. Default: 60. */
  readonly codeSeconds?: number;
  /** How long a device code is valid, in seconds. Default: 600. */
  readonly deviceCodeSeconds?: number;
  /** The minimum seconds between device code polls. Default: 5. */
  readonly deviceInterval?: number;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<OAuthServer>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** The client metadata a registration sets (RFC 7591 section 2). */
export interface OAuthClientMetadata {
  readonly name?: string;
  /** Absolute `https` URIs, or `http` on a loopback host; no fragment. */
  readonly redirectUris?: readonly string[];
  /** Default: `["authorization_code"]`. */
  readonly grantTypes?: readonly OAuthGrantType[];
  /** `none` registers a public client without a secret. Default: `client_secret_basic`. */
  readonly tokenEndpointAuthMethod?: OAuthClientAuthMethod;
  /** Space-separated scopes the client may ask for. */
  readonly scope?: string;
  /** Other RFC 7591 metadata, such as `logo_uri` or `software_id`, stored as given. */
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** A registered client, without its secret. */
export interface OAuthClient {
  readonly clientId: string;
  readonly name: string | null;
  readonly redirectUris: readonly string[];
  readonly grantTypes: readonly OAuthGrantType[];
  readonly tokenEndpointAuthMethod: OAuthClientAuthMethod;
  readonly scope: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly createdBy: string | null;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `registerClient` returns. The secret and token are shown once and stored hashed. */
export interface RegisteredOAuthClient {
  readonly client: OAuthClient;
  /** `null` for a public client (`tokenEndpointAuthMethod: "none"`). */
  readonly clientSecret: string | null;
  /** The RFC 7592 registration access token for reading and updating the client. */
  readonly registrationAccessToken: string;
}

export interface RegisterClientOptions {
  /** The user who registered the client, when one did. */
  readonly createdBy?: string;
  /**
   * A client id to use instead of a generated one. It has to match the
   * module's `clientIdPattern`; the database refuses it otherwise.
   */
  readonly clientId?: string;
}

export interface AuthorizationCodeRequest {
  readonly clientId: string;
  /** The user who consented. */
  readonly userId: string;
  /** The `redirect_uri` of the request, when it named one. */
  readonly redirectUri?: string;
  readonly scope?: string;
  readonly codeChallenge: string;
  /** Must be `S256`; `plain` and any other method are refused. */
  readonly codeChallengeMethod: string;
  /** The OpenID Connect `nonce`, returned by `redeemAuthorizationCode`. */
  readonly nonce?: string;
  /**
   * The RFC 8707 `resource` indicators of the request: the APIs the token may
   * be used at. `redeemAuthorizationCode` returns them for the token's `aud`.
   */
  readonly resource?: readonly string[];
}

/** What `createAuthorizationCode` returns. */
export interface IssuedAuthorizationCode {
  /** The code for the redirect; only its hash is stored. */
  readonly code: string;
  readonly grantId: string;
  readonly expiresAt: Temporal.Instant;
}

export interface AuthorizationCodeRedemption {
  readonly code: string;
  readonly clientId: string;
  /** Must match the authorization request's `redirect_uri`. */
  readonly redirectUri?: string;
  readonly codeVerifier: string;
  /**
   * The `resource` of the token request. It has to be a subset of the code's
   * resources (RFC 8707 section 2.2); anything else is refused.
   */
  readonly resource?: readonly string[];
}

/** A code or device code exchanged once: who to issue tokens for. */
export interface OAuthAuthorization {
  readonly userId: string;
  readonly clientId: string;
  readonly grantId: string;
  readonly scope: string;
  readonly nonce: string | null;
  /** The RFC 8707 resources the token is for; empty when the request named none. */
  readonly resource: readonly string[];
}

/** What `createDeviceCode` returns (RFC 8628 section 3.2). */
export interface IssuedDeviceCode {
  readonly deviceCode: string;
  /** Eight letters, shown as `XXXX-XXXX`. */
  readonly userCode: string;
  readonly expiresIn: number;
  readonly interval: number;
}

/** The pending request behind a user code, for the verification page. */
export interface DeviceRequest {
  readonly clientId: string;
  readonly scope: string;
  readonly resource: readonly string[];
  readonly expiresAt: Temporal.Instant;
}

/** A device code poll, mapped to the RFC 8628 section 3.5 token responses. */
export type DeviceCodePoll =
  | { readonly status: "ok"; readonly authorization: OAuthAuthorization }
  | { readonly status: "authorization_pending"; readonly interval: number }
  | { readonly status: "slow_down"; readonly interval: number }
  | { readonly status: "access_denied" }
  | { readonly status: "expired_token" }
  | { readonly status: "invalid_grant" };

/** A user's consent for a client, which the tokens issued under it carry as `grant_id`. */
export interface OAuthGrant {
  readonly id: string;
  readonly userId: string;
  readonly clientId: string;
  readonly clientName: string | null;
  readonly scopes: readonly string[];
  /** Every resource the user consented to for this client. */
  readonly resource: readonly string[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly revokedAt: Temporal.Instant | null;
}

export interface ListGrantsOptions {
  readonly includeRevoked?: boolean;
}

export interface RevokeTokenOptions {
  readonly grantId?: string;
}

/**
 * The `oauth-server` storage as typed calls. Service role only, except the
 * signed-in user's `my_oauth_grants` and `revoke_my_oauth_grant`.
 */
export interface OAuthServer {
  /** Registers a client (RFC 7591) and returns its secret and registration token once. */
  registerClient(
    metadata: OAuthClientMetadata,
    options?: RegisterClientOptions,
  ): AsyncResult<RegisteredOAuthClient>;
  readClient(clientId: string): AsyncResult<OAuthClient | null>;
  /** Changes the given metadata (RFC 7592); `null` for an unknown client. */
  updateClient(
    clientId: string,
    metadata: Omit<OAuthClientMetadata, "tokenEndpointAuthMethod">,
  ): AsyncResult<OAuthClient | null>;
  /** A new secret for a confidential client; `null` for an unknown or public client. */
  rotateSecret(clientId: string): AsyncResult<string | null>;
  /** Deletes the client, its grants and its codes. */
  deleteClient(clientId: string): AsyncResult<boolean>;
  /** The client when the secret matches, `null` otherwise. Pass `null` for a public client. */
  verifyClient(
    clientId: string,
    secret: string | null,
  ): AsyncResult<OAuthClient | null>;
  /** Whether the RFC 7592 registration access token belongs to the client. */
  verifyRegistrationToken(
    clientId: string,
    token: string,
  ): AsyncResult<boolean>;
  /** Stores a code after the user consented, under their grant for the client. */
  createAuthorizationCode(
    request: AuthorizationCodeRequest,
  ): AsyncResult<IssuedAuthorizationCode>;
  /**
   * Exchanges a code once, checking the client, redirect URI and PKCE
   * verifier. `null` for any mismatch; a reused code also revokes its grant.
   */
  redeemAuthorizationCode(
    redemption: AuthorizationCodeRedemption,
  ): AsyncResult<OAuthAuthorization | null>;
  createDeviceCode(
    clientId: string,
    scope?: string,
    resource?: readonly string[],
  ): AsyncResult<IssuedDeviceCode>;
  /** The pending request for a user code as typed, dashes and case ignored. */
  deviceRequest(userCode: string): AsyncResult<DeviceRequest | null>;
  approveDeviceCode(userCode: string, userId: string): AsyncResult<boolean>;
  denyDeviceCode(userCode: string, userId: string): AsyncResult<boolean>;
  pollDeviceCode(
    deviceCode: string,
    clientId: string,
    resource?: readonly string[],
  ): AsyncResult<DeviceCodePoll>;
  listGrants(
    userId: string,
    options?: ListGrantsOptions,
  ): AsyncResult<readonly OAuthGrant[]>;
  /** Revokes a grant: every token carrying its `grant_id` fails `isRevoked`. */
  revokeGrant(grantId: string): AsyncResult<boolean>;
  /** Puts an access token's `jti` on the revocation list until `expiresAt`. */
  revokeToken(
    jti: string,
    expiresAt: Temporal.Instant,
    options?: RevokeTokenOptions,
  ): AsyncResult<boolean>;
  /**
   * Whether a token is revoked by `jti` or by its grant. A grant id that is
   * unknown counts as revoked. Fits `accessTokenResolver({ revocation })`.
   */
  isRevoked(jti: string, grantId: string | undefined): AsyncResult<boolean>;
  /** Deletes expired codes, device codes and revocation entries. */
  purge(): AsyncResult<number>;
}

// RFC 8628 section 6.1: consonants only, so a code spells no word.
const USER_CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ";
const USER_CODE_LENGTH = 8;
const VERIFIER = /^[A-Za-z0-9._~-]{43,128}$/;
const CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
const SCRIPT_SCHEMES = new Set(["javascript", "vbscript", "data"]);
const LOOPBACK = new Set(["localhost", "127.0.0.1", "[::1]"]);

const invalid = (message: string, hint: string): AsyncResult<never> =>
  AsyncResult.err(dbError("invalid_input", message, { hint }));

function userCode(): string {
  const out: string[] = [];
  const limit = 256 - (256 % USER_CODE_ALPHABET.length);

  while (out.length < USER_CODE_LENGTH) {
    for (const byte of crypto.getRandomValues(new Uint8Array(16))) {
      if (byte < limit && out.length < USER_CODE_LENGTH) {
        out.push(USER_CODE_ALPHABET.charAt(byte % USER_CODE_ALPHABET.length));
      }
    }
  }

  return out.join("");
}

const normalizeUserCode = (code: string): string =>
  code.toUpperCase().replaceAll(/[^A-Z0-9]/g, "");

/** A redirect URI RFC 9700 section 2.1 allows: absolute, no fragment, https or loopback http. */
function redirectUriProblem(uri: string): string | undefined {
  if (!URL.canParse(uri)) {
    return `${uri} is not an absolute URI`;
  }

  const url = new URL(uri);

  if (url.hash !== "" || uri.includes("#")) {
    return `${uri} has a fragment`;
  }

  if (url.protocol === "http:" && !LOOPBACK.has(url.hostname)) {
    return `${uri} uses http on a host that is not loopback`;
  }

  if (SCRIPT_SCHEMES.has(url.protocol.slice(0, -1))) {
    return `${uri} uses a scheme a redirect can't`;
  }

  return undefined;
}

async function s256(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );

  return toBase64Url(new Uint8Array(digest));
}

function clientOf(value: unknown, fn: string): OAuthClient {
  const row = recordOf(value, fn);

  return {
    clientId: textOf(row["clientId"]),
    name: nullableText(row["name"]),
    redirectUris: stringsOf(row["redirectUris"]),
    grantTypes: stringsOf(row["grantTypes"]).map((type) =>
      enumOrThrow(type, GRANT_TYPES, "grant type"),
    ),
    tokenEndpointAuthMethod: enumOrThrow(
      row["tokenEndpointAuthMethod"],
      AUTH_METHODS,
      "token endpoint auth method",
    ),
    scope: nullableText(row["scope"]),
    metadata: recordOrEmpty(row["metadata"]),
    createdBy: nullableText(row["createdBy"]),
    createdAt: instantOf(row["createdAt"]),
    updatedAt: instantOf(row["updatedAt"]),
  };
}

const optionalClient = (value: unknown, fn: string): OAuthClient | null =>
  value === null || value === undefined ? null : clientOf(value, fn);

function grantOf(row: Record<string, unknown>): OAuthGrant {
  return {
    id: textOf(row["id"]),
    userId: textOf(row["userId"]),
    clientId: textOf(row["clientId"]),
    clientName: nullableText(row["clientName"]),
    scopes: stringsOf(row["scopes"]),
    resource: stringsOf(row["resource"] ?? []),
    createdAt: instantOf(row["createdAt"]),
    updatedAt: instantOf(row["updatedAt"]),
    revokedAt: nullableInstant(row["revokedAt"]),
  };
}

function authorizationOf(row: Record<string, unknown>): OAuthAuthorization {
  return {
    userId: textOf(row["userId"]),
    clientId: textOf(row["clientId"]),
    grantId: textOf(row["grantId"]),
    scope: nullableText(row["scope"]) ?? "",
    nonce: nullableText(row["nonce"]),
    resource: stringsOf(row["resource"] ?? []),
  };
}

function pollOf(value: unknown): DeviceCodePoll {
  const row = recordOf(value, "poll_oauth_device_code");

  const status = enumOrThrow(
    row["status"],
    [
      "ok",
      "authorization_pending",
      "slow_down",
      "access_denied",
      "expired_token",
      "invalid_grant",
    ] as const,
    "device code status",
  );

  switch (status) {
    case "ok": {
      return { status, authorization: authorizationOf(row) };
    }

    case "authorization_pending":
    case "slow_down": {
      return { status, interval: Number(row["interval"]) };
    }

    case "access_denied":
    case "expired_token":
    case "invalid_grant": {
      return { status };
    }

    default: {
      const unreachable: never = status;
      throw new TypeError(`Unknown device code status ${String(unreachable)}`);
    }
  }
}

/**
 * The `oauth-server` SQL module as typed calls: secrets, codes and
 * registration tokens are generated and hashed here, and only their SHA-256
 * reaches the database. It stores what an authorization server needs and
 * issues no tokens; sign them with `createSigningKeys` and verify them with
 * `accessTokenResolver`.
 */
export function createOAuthServer(options: OAuthServerOptions): OAuthServer {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const codeSeconds = options.codeSeconds ?? 60;
  const deviceSeconds = options.deviceCodeSeconds ?? 600;
  const deviceInterval = options.deviceInterval ?? 5;

  const checkRedirects = (
    uris: readonly string[] | undefined,
  ): AsyncResult<never> | undefined => {
    for (const uri of uris ?? []) {
      const problem = redirectUriProblem(uri);

      if (problem !== undefined) {
        return invalid(problem, "OAUTH_REDIRECT_URI_INVALID");
      }
    }

    return undefined;
  };

  const decide = (code: string, userId: string, approve: boolean) =>
    call(
      "decide_oauth_device_code",
      { user_code: normalizeUserCode(code), user_id: userId, approve },
      (value) => value === true,
    );

  const client: OAuthServer = {
    registerClient: (metadata, registerOptions = {}) => {
      const method = metadata.tokenEndpointAuthMethod ?? "client_secret_basic";
      const grantTypes = metadata.grantTypes ?? ["authorization_code"];
      const bad = checkRedirects(metadata.redirectUris);

      if (bad) {
        return bad;
      }

      if (
        grantTypes.includes("authorization_code") &&
        (metadata.redirectUris ?? []).length === 0
      ) {
        return invalid(
          "A client that uses authorization codes needs a redirect URI",
          "OAUTH_REDIRECT_URI_INVALID",
        );
      }

      const clientId = registerOptions.clientId ?? randomToken(16);
      const secret = method === "none" ? null : randomToken(32);
      const registrationToken = randomToken(32);

      return run(async () => ({
        secretHash: secret === null ? null : await sha256Hex(secret),
        tokenHash: await sha256Hex(registrationToken),
      })).andThen((hashes) =>
        call(
          "register_oauth_client",
          {
            client_id: clientId,
            secret_hash: hashes.secretHash,
            registration_token_hash: hashes.tokenHash,
            client_name: metadata.name ?? null,
            redirect_uris: metadata.redirectUris ?? [],
            grant_types: grantTypes,
            token_endpoint_auth_method: method,
            scope: metadata.scope ?? null,
            metadata: metadata.metadata ?? {},
            created_by: registerOptions.createdBy ?? null,
          },
          (value) => ({
            client: clientOf(value, "register_oauth_client"),
            clientSecret: secret,
            registrationAccessToken: registrationToken,
          }),
        ),
      );
    },
    readClient: (clientId) =>
      call("oauth_client", { client_id: clientId }, (value) =>
        optionalClient(value, "oauth_client"),
      ),
    updateClient: (clientId, metadata) => {
      const bad = checkRedirects(metadata.redirectUris);

      if (bad) {
        return bad;
      }

      return call(
        "update_oauth_client",
        {
          client_id: clientId,
          client_name: metadata.name ?? null,
          redirect_uris: metadata.redirectUris ?? null,
          grant_types: metadata.grantTypes ?? null,
          scope: metadata.scope ?? null,
          metadata: metadata.metadata ?? null,
        },
        (value) => optionalClient(value, "update_oauth_client"),
      );
    },
    rotateSecret: (clientId) => {
      const secret = randomToken(32);

      return run(() => sha256Hex(secret)).andThen((hash) =>
        call(
          "rotate_oauth_client_secret",
          { client_id: clientId, secret_hash: hash },
          (value) => (value === true ? secret : null),
        ),
      );
    },
    deleteClient: (clientId) =>
      call(
        "delete_oauth_client",
        { client_id: clientId },
        (value) => value === true,
      ),
    verifyClient: (clientId, secret) =>
      run(async () => (secret === null ? null : sha256Hex(secret))).andThen(
        (hash) =>
          call(
            "verify_oauth_client",
            { client_id: clientId, secret_hash: hash },
            (value) => optionalClient(value, "verify_oauth_client"),
          ),
      ),
    verifyRegistrationToken: (clientId, token) =>
      run(() => sha256Hex(token)).andThen((hash) =>
        call(
          "verify_oauth_registration_token",
          { client_id: clientId, token_hash: hash },
          (value) => value === true,
        ),
      ),
    createAuthorizationCode: (request) => {
      if (request.codeChallengeMethod !== "S256") {
        return invalid(
          "Only the S256 code challenge method is accepted",
          "OAUTH_PKCE_INVALID",
        );
      }

      if (!CHALLENGE.test(request.codeChallenge)) {
        return invalid(
          "The code challenge is not a base64url SHA-256 digest",
          "OAUTH_PKCE_INVALID",
        );
      }

      const code = randomToken(32);
      const expiresAt = temporal().Now.instant().add({ seconds: codeSeconds });

      return run(() => sha256Hex(code)).andThen((hash) =>
        call(
          "create_oauth_authorization_code",
          {
            code_hash: hash,
            client_id: request.clientId,
            user_id: request.userId,
            redirect_uri: request.redirectUri ?? null,
            scope: request.scope ?? "",
            code_challenge: request.codeChallenge,
            ttl: `${String(codeSeconds)} seconds`,
            nonce: request.nonce ?? null,
            resource: request.resource ?? null,
          },
          (value) => ({
            code,
            grantId: textOf(
              recordOf(value, "create_oauth_authorization_code")["grantId"],
            ),
            expiresAt,
          }),
        ),
      );
    },
    redeemAuthorizationCode: (redemption) => {
      if (!VERIFIER.test(redemption.codeVerifier)) {
        return AsyncResult.ok(null);
      }

      return run(async () => ({
        hash: await sha256Hex(redemption.code),
        challenge: await s256(redemption.codeVerifier),
      })).andThen(({ hash, challenge }) =>
        call(
          "redeem_oauth_authorization_code",
          {
            code_hash: hash,
            client_id: redemption.clientId,
            redirect_uri: redemption.redirectUri ?? null,
            code_challenge: challenge,
            resource: redemption.resource ?? null,
          },
          (value) => {
            const row = recordOf(value, "redeem_oauth_authorization_code");

            return row["status"] === "ok" ? authorizationOf(row) : null;
          },
        ),
      );
    },
    createDeviceCode: (clientId, scope, resource) => {
      const deviceCode = randomToken(32);
      const code = userCode();

      return run(() => sha256Hex(deviceCode)).andThen((hash) =>
        call(
          "create_oauth_device_code",
          {
            device_code_hash: hash,
            user_code: code,
            client_id: clientId,
            scope: scope ?? "",
            ttl: `${String(deviceSeconds)} seconds`,
            poll_interval: deviceInterval,
            resource: resource ?? null,
          },
          () => ({
            deviceCode,
            userCode: `${code.slice(0, 4)}-${code.slice(4)}`,
            expiresIn: deviceSeconds,
            interval: deviceInterval,
          }),
        ),
      );
    },
    deviceRequest: (code) =>
      call(
        "oauth_device_request",
        { user_code: normalizeUserCode(code) },
        (value) => {
          if (value === null || value === undefined) {
            return null;
          }

          const row = recordOf(value, "oauth_device_request");

          return {
            clientId: textOf(row["clientId"]),
            scope: nullableText(row["scope"]) ?? "",
            resource: stringsOf(row["resource"] ?? []),
            expiresAt: instantOf(row["expiresAt"]),
          };
        },
      ),
    approveDeviceCode: (code, userId) => decide(code, userId, true),
    denyDeviceCode: (code, userId) => decide(code, userId, false),
    pollDeviceCode: (deviceCode, clientId, resource) =>
      run(() => sha256Hex(deviceCode)).andThen((hash) =>
        call(
          "poll_oauth_device_code",
          {
            device_code_hash: hash,
            client_id: clientId,
            resource: resource ?? null,
          },
          pollOf,
        ),
      ),
    listGrants: (userId, listOptions = {}) =>
      call(
        "list_oauth_grants",
        {
          user_id: userId,
          include_revoked: listOptions.includeRevoked === true,
        },
        (value) => recordsOf(value, "list_oauth_grants").map(grantOf),
      ),
    revokeGrant: (grantId) =>
      call(
        "revoke_oauth_grant",
        { grant_id: grantId },
        (value) => value === true,
      ),
    revokeToken: (jti, expiresAt, revokeOptions = {}) =>
      call(
        "revoke_oauth_token",
        {
          jti,
          expires_at: expiresAt.toString(),
          grant_id: revokeOptions.grantId ?? null,
        },
        (value) => value === true,
      ),
    isRevoked: (jti, grantId) =>
      call(
        "is_oauth_token_revoked",
        { jti, grant_id: grantId ?? null },
        (value) => value !== false,
      ),
    purge: () => call("purge_oauth_server", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "oauth-server",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
