import type { Jwks } from "../core/jws.ts";
import type { VerifiedSdJwt } from "./sd-jwt.ts";

import { decodeJwtPayload } from "../core/base64.ts";
import { isList, isRecord } from "../core/guards.ts";
import { verifySdJwt } from "./sd-jwt.ts";
import { CredentialError, randomUrl } from "./shared.ts";
import { readStatus } from "./status-list.ts";

/** One credential a verifier asks for, in DCQL (OpenID4VP 1.0 section 6). */
export interface CredentialQuery {
  /** The key the response's `vp_token` uses for this credential. */
  readonly id: string;
  readonly vct: string;
  /** The top-level claim names the wallet has to disclose. */
  readonly claims: readonly string[];
}

/** A DCQL query for `dc+sd-jwt` credentials. */
export function dcqlQuery(
  credentials: readonly CredentialQuery[],
): Readonly<Record<string, unknown>> {
  return {
    credentials: credentials.map((query) => ({
      id: query.id,
      format: "dc+sd-jwt",
      meta: { vct_values: [query.vct] },
      claims: query.claims.map((name) => ({ path: [name] })),
    })),
  };
}

export interface PresentationRequestOptions {
  /** The URL the wallet posts the response to (`response_mode=direct_post`). */
  readonly responseUri: string;
  readonly credentials: readonly CredentialQuery[];
}

/** What the verifier keeps for one request until the response arrives. */
export interface PresentationRequest {
  /** The client identifier; the key binding JWT's `aud` has to equal it. */
  readonly clientId: string;
  readonly nonce: string;
  readonly state: string;
  readonly credentials: readonly CredentialQuery[];
}

export interface CreatedPresentationRequest {
  readonly request: PresentationRequest;
  /** The authorization request parameters, for a QR code or a link. */
  readonly params: Readonly<Record<string, string>>;
  /** An `openid4vp://authorize?...` link. */
  readonly uri: string;
}

/**
 * An unsigned OpenID4VP request with the `redirect_uri:` client identifier
 * prefix and `response_mode=direct_post`. Store `request` (keyed by `state`)
 * and hand it to `verifyPresentationResponse` when the wallet posts back.
 */
export function createPresentationRequest(
  options: PresentationRequestOptions,
): CreatedPresentationRequest {
  const request: PresentationRequest = {
    clientId: `redirect_uri:${options.responseUri}`,
    nonce: randomUrl(24),
    state: randomUrl(16),
    credentials: options.credentials,
  };

  const params = {
    client_id: request.clientId,
    response_type: "vp_token",
    response_mode: "direct_post",
    response_uri: options.responseUri,
    nonce: request.nonce,
    state: request.state,
    dcql_query: JSON.stringify(dcqlQuery(options.credentials)),
  };

  return {
    request,
    params,
    uri: `openid4vp://authorize?${new URLSearchParams(params).toString()}`,
  };
}

/**
 * Where `verifyPresentationResponse` finds an issuer's keys; `undefined`
 * rejects it.
 */
export type IssuerKeys = (
  issuer: string,
) => PromiseLike<Jwks | undefined> | Jwks | undefined;

export interface VerifyPresentationOptions {
  readonly request: PresentationRequest;
  readonly issuers: IssuerKeys;
  readonly now?: Temporal.Instant;
  /**
   * Fetches the Status List Token a credential references. Without it the
   * revocation bit is not checked.
   */
  readonly fetchStatusList?: (uri: string) => PromiseLike<string>;
}

export interface VerifiedPresentation {
  readonly id: string;
  readonly issuer: string;
  readonly vct: string;
  readonly claims: Readonly<Record<string, unknown>>;
}

export type PresentationOutcome =
  | {
      readonly ok: true;
      readonly presentations: readonly VerifiedPresentation[];
    }
  | { readonly ok: false; readonly code: string; readonly message: string };

/** The form fields a wallet posts to `response_uri`. */
export interface PresentationResponse {
  readonly vp_token?: string | Readonly<Record<string, unknown>>;
  readonly state?: string;
}

function tokensOf(value: unknown): string[] | undefined {
  if (typeof value === "string") {
    return [value];
  }

  return isList(value) && value.every((item) => typeof item === "string")
    ? [...value]
    : undefined;
}

/**
 * Verifies a wallet's response against the request: every queried credential is
 * present, signed by a trusted issuer, of the right `vct`, key bound to this
 * request's audience and nonce, discloses the asked-for claims and (with
 * `fetchStatusList`) is not revoked. It never throws for a bad response.
 */
export async function verifyPresentationResponse(
  response: PresentationResponse,
  options: VerifyPresentationOptions,
): Promise<PresentationOutcome> {
  const { request } = options;

  const fail = (code: string, message: string): PresentationOutcome => ({
    ok: false,
    code,
    message,
  });

  if (response.state !== request.state) {
    return fail("OPENID4VP_STATE", "The state does not match the request");
  }

  let token: unknown = response.vp_token;

  if (typeof token === "string" && token.trimStart().startsWith("{")) {
    try {
      token = JSON.parse(token);
    } catch {
      return fail("OPENID4VP_VP_TOKEN", "vp_token is not valid JSON");
    }
  }

  if (!isRecord(token)) {
    return fail(
      "OPENID4VP_VP_TOKEN",
      "vp_token is a JSON object keyed by query id",
    );
  }

  const presentations: VerifiedPresentation[] = [];

  for (const query of request.credentials) {
    const tokens = tokensOf(token[query.id]);

    if (tokens?.length !== 1 || tokens[0] === undefined) {
      return fail(
        "OPENID4VP_MISSING",
        `Exactly one presentation for ${query.id} is required`,
      );
    }

    try {
      const issuer = issuerOf(tokens[0]);

      const jwks =
        issuer === undefined ? undefined : await options.issuers(issuer);

      if (jwks === undefined) {
        return fail(
          "OPENID4VP_ISSUER",
          `The issuer of ${query.id} is not trusted`,
        );
      }

      const verified: VerifiedSdJwt = await verifySdJwt(tokens[0], {
        jwks,
        vct: query.vct,
        requireKeyBinding: true,
        audience: request.clientId,
        nonce: request.nonce,
        ...(options.now === undefined ? {} : { now: options.now }),
      });

      const missing = query.claims.filter((name) => !(name in verified.claims));

      if (missing.length > 0) {
        return fail(
          "OPENID4VP_CLAIMS",
          `${query.id} lacks ${missing.join(", ")}`,
        );
      }

      const revoked = await isRevoked(verified, jwks, options);

      if (revoked) {
        return fail("OPENID4VP_REVOKED", `${query.id} has been revoked`);
      }

      presentations.push({
        id: query.id,
        issuer: String(verified.payload["iss"]),
        vct: String(verified.payload["vct"]),
        claims: verified.claims,
      });
    } catch (error) {
      if (error instanceof CredentialError) {
        return fail(error.code, error.message);
      }

      throw error;
    }
  }

  return { ok: true, presentations };
}

/**
 * The unverified `iss` of an SD-JWT, only used to pick which keys to verify
 * with.
 */
function issuerOf(token: string): string | undefined {
  const claims = decodeJwtPayload(token.split("~")[0] ?? "");
  const issuer = claims?.["iss"];

  return typeof issuer === "string" ? issuer : undefined;
}

async function isRevoked(
  verified: VerifiedSdJwt,
  jwks: Jwks,
  options: VerifyPresentationOptions,
): Promise<boolean> {
  const status = verified.payload["status"];
  const list = isRecord(status) ? status["status_list"] : undefined;

  if (options.fetchStatusList === undefined || !isRecord(list)) {
    return false;
  }

  if (typeof list["uri"] !== "string" || typeof list["idx"] !== "number") {
    throw new CredentialError(
      "STATUS_LIST_CLAIMS",
      "status_list needs uri and idx",
    );
  }

  const bit = await readStatus(await options.fetchStatusList(list["uri"]), {
    jwks,
    uri: list["uri"],
    index: list["idx"],
    ...(options.now === undefined ? {} : { now: options.now }),
  });

  return bit === 1;
}
