import type { Jwk } from "../core/jws.ts";
import type { StatusReference } from "./sd-jwt.ts";
import type { CredentialSigner } from "./shared.ts";

import { decodeJwtHeader, toBase64Url } from "../core/base64.ts";
import { isList, isRecord } from "../core/guards.ts";
import { JwsError, publicJwk, verifyCompact } from "../core/jws.ts";
import { issueJwtVc } from "./jwt-vc.ts";
import { issueSdJwt } from "./sd-jwt.ts";
import { epochSeconds, randomUrl, sha256Url } from "./shared.ts";
import { bitstringEntry } from "./status-list.ts";

/** The pre-authorized code grant type (OpenID4VCI 1.0 section 3.5). */
export const PRE_AUTHORIZED_GRANT =
  "urn:ietf:params:oauth:grant-type:pre-authorized_code";

/** The JWS `typ` of a key proof (OpenID4VCI 1.0 appendix F.1). */
export const PROOF_TYP = "openid4vci-proof+jwt";

/** One credential the issuer offers, keyed by `credential_configuration_id`. */
export interface CredentialConfiguration {
  readonly id: string;
  readonly format: "dc+sd-jwt" | "jwt_vc_json";
  /** The credential type of an `dc+sd-jwt` configuration (`vct`). */
  readonly vct?: string;
  /** The types after `VerifiableCredential` of a `jwt_vc_json` configuration. */
  readonly types?: readonly string[];
  readonly scope?: string;
  /** The claim names a holder can disclose one by one (`dc+sd-jwt` only). */
  readonly disclosable?: readonly string[];
  /** How long an issued credential stays valid; unset means it does not expire. */
  readonly validFor?: Temporal.Duration;
  /** Wallet-facing display metadata, passed through to the issuer metadata. */
  readonly display?: readonly Readonly<Record<string, unknown>>[];
}

/**
 * Where an issued credential's claims come from. `subject` is the reference the
 * offer was created with, such as `qualification:<id>`; the source answers
 * `undefined` when it no longer qualifies, and issuance then stops.
 */
export interface CredentialSource {
  readonly id: string;
  readonly configuration: CredentialConfiguration;
  claims(
    subject: string,
  ): PromiseLike<Readonly<Record<string, unknown>> | undefined>;
}

/** What `IssuanceStore.saveOffer` keeps for a pre-authorized code. */
export interface PendingOffer {
  readonly configurationId: string;
  readonly subject: string;
  readonly txCodeHash?: string;
  readonly expiresAt: Temporal.Instant;
}

/** What an access token stands for until the credential endpoint takes it. */
export interface Grant {
  readonly configurationId: string;
  readonly subject: string;
  readonly expiresAt: Temporal.Instant;
}

/** One credential the issuer signed, for the app's own records. */
export interface IssuedCredential {
  readonly configurationId: string;
  readonly subject: string;
  readonly format: CredentialConfiguration["format"];
  readonly status?: StatusReference;
  readonly issuedAt: Temporal.Instant;
  readonly expiresAt?: Temporal.Instant;
}

/**
 * Where the issuer keeps its single-use state. Every `take` and `redeem` has to
 * be atomic (a `delete ... returning`), or two concurrent requests could both
 * succeed. Only hashes of codes, tokens and nonces are stored.
 */
export interface IssuanceStore {
  saveOffer(codeHash: string, offer: PendingOffer): PromiseLike<void>;
  /** Removes and returns the offer, or `undefined` when unknown or expired. */
  redeemOffer(
    codeHash: string,
    now: Temporal.Instant,
  ): PromiseLike<PendingOffer | undefined>;
  saveGrant(tokenHash: string, grant: Grant): PromiseLike<void>;
  /** Removes and returns the grant, or `undefined` when unknown or expired. */
  takeGrant(
    tokenHash: string,
    now: Temporal.Instant,
  ): PromiseLike<Grant | undefined>;
  saveNonce(nonceHash: string, expiresAt: Temporal.Instant): PromiseLike<void>;
  /** Removes the nonce; `false` when unknown or expired. */
  takeNonce(nonceHash: string, now: Temporal.Instant): PromiseLike<boolean>;
  /** The next free revocation index of the configuration's status list. */
  allocateStatus(
    configurationId: string,
  ): PromiseLike<StatusReference | undefined>;
  recordIssued(credential: IssuedCredential): PromiseLike<void>;
}

/** An in-memory `IssuanceStore` for tests and local development. */
export function memoryIssuanceStore(
  statusUri?: (configurationId: string) => string,
): IssuanceStore {
  const offers = new Map<string, PendingOffer>();
  const grants = new Map<string, Grant>();
  const nonces = new Map<string, Temporal.Instant>();
  const counters = new Map<string, number>();

  const live = (at: Temporal.Instant, now: Temporal.Instant): boolean =>
    Temporal.Instant.compare(at, now) > 0;

  return {
    saveOffer(hash, offer) {
      offers.set(hash, offer);

      return Promise.resolve();
    },
    redeemOffer(hash, now) {
      const offer = offers.get(hash);
      offers.delete(hash);

      return Promise.resolve(
        offer !== undefined && live(offer.expiresAt, now) ? offer : undefined,
      );
    },
    saveGrant(hash, grant) {
      grants.set(hash, grant);

      return Promise.resolve();
    },
    takeGrant(hash, now) {
      const grant = grants.get(hash);
      grants.delete(hash);

      return Promise.resolve(
        grant !== undefined && live(grant.expiresAt, now) ? grant : undefined,
      );
    },
    saveNonce(hash, expiresAt) {
      nonces.set(hash, expiresAt);

      return Promise.resolve();
    },
    takeNonce(hash, now) {
      const expiresAt = nonces.get(hash);
      nonces.delete(hash);

      return Promise.resolve(expiresAt !== undefined && live(expiresAt, now));
    },
    allocateStatus(configurationId) {
      if (statusUri === undefined) {
        return Promise.resolve(undefined);
      }

      const idx = counters.get(configurationId) ?? 0;
      counters.set(configurationId, idx + 1);

      return Promise.resolve({ idx, uri: statusUri(configurationId) });
    },
    recordIssued() {
      return Promise.resolve();
    },
  };
}

/** What an endpoint answers; `toResponse` turns it into a `Response`. */
export interface EndpointResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
  readonly headers: Readonly<Record<string, string>>;
}

export function toResponse(result: EndpointResult): Response {
  return Response.json(result.body, {
    status: result.status,
    headers: { "content-type": "application/json", ...result.headers },
  });
}

const NO_STORE = { "cache-control": "no-store" } as const;

const failure = (
  status: number,
  error: string,
  description: string,
  headers: Readonly<Record<string, string>> = {},
): EndpointResult => ({
  status,
  body: { error, error_description: description },
  headers: { ...NO_STORE, ...headers },
});

export interface CredentialIssuerOptions {
  /** The issuer identifier: an `https` URL without a query or fragment. */
  readonly issuer: string;
  readonly signer: CredentialSigner;
  readonly sources: readonly CredentialSource[];
  readonly store: IssuanceStore;
  readonly endpoints: {
    readonly token: string;
    readonly credential: string;
    readonly nonce: string;
  };
  /** Seconds a pre-authorized code lives. Default: 600. */
  readonly offerTtl?: number;
  /** Seconds an access token lives. Default: 300. */
  readonly tokenTtl?: number;
  /** Seconds a `c_nonce` lives. Default: 300. */
  readonly nonceTtl?: number;
  /** Replaces the clock in tests. */
  readonly now?: () => Temporal.Instant;
}

export interface CreateOfferOptions {
  readonly configurationId: string;
  /** The source's reference for what is issued, such as `qualification:<id>`. */
  readonly subject: string;
  /** A transaction code the holder enters in the wallet; send it out of band. */
  readonly txCode?: string;
}

export interface CredentialOffer {
  /** The `openid-credential-offer://` link or QR payload for the wallet. */
  readonly uri: string;
  readonly offer: Readonly<Record<string, unknown>>;
  readonly expiresAt: Temporal.Instant;
}

export interface CredentialIssuer {
  /** `/.well-known/openid-credential-issuer`. */
  metadata(): Readonly<Record<string, unknown>>;
  /** `/.well-known/oauth-authorization-server`, for the token endpoint. */
  authorizationServerMetadata(): Readonly<Record<string, unknown>>;
  createOffer(options: CreateOfferOptions): Promise<CredentialOffer>;
  /** The token endpoint, for a form-encoded body already parsed to a record. */
  token(
    params: Readonly<Record<string, string | undefined>>,
  ): Promise<EndpointResult>;
  nonce(): Promise<EndpointResult>;
  /**
   * The credential endpoint: the `Authorization` header and the parsed JSON
   * body.
   */
  credential(
    authorization: string | null | undefined,
    body: unknown,
  ): Promise<EndpointResult>;
}

const PROOF_LEEWAY_SECONDS = 300;

/**
 * An OpenID4VCI 1.0 issuer for the pre-authorized code flow. It is
 * transport-free: mount `token`, `nonce` and `credential` on any route and wrap
 * the result with `toResponse`.
 */
export function createCredentialIssuer(
  options: CredentialIssuerOptions,
): CredentialIssuer {
  const { issuer, signer, store } = options;
  const clock = options.now ?? (() => Temporal.Now.instant());
  const sources = new Map(options.sources.map((s) => [s.configuration.id, s]));

  const inSeconds = (seconds: number): Temporal.Instant =>
    clock().add({ seconds });

  const bearer = (
    authorization: string | null | undefined,
  ): string | undefined => {
    const match = /^Bearer ([A-Za-z0-9._~+/-]+=*)$/.exec(authorization ?? "");

    return match?.[1];
  };

  const unauthorized = (): EndpointResult =>
    failure(401, "invalid_token", "The access token is invalid or expired", {
      "www-authenticate": 'Bearer error="invalid_token"',
    });

  async function verifyProof(
    proofs: unknown,
  ): Promise<{ holderKey: Jwk } | EndpointResult> {
    const list = isRecord(proofs) ? proofs["jwt"] : undefined;

    if (!isList(list) || list.length !== 1 || typeof list[0] !== "string") {
      return failure(400, "invalid_proof", "proofs.jwt needs exactly one JWT");
    }

    const proof = list[0];
    const header = decodeJwtHeader(proof);
    const claimed = header?.["jwk"];

    if (!isRecord(claimed) || "d" in claimed) {
      return failure(
        400,
        "invalid_proof",
        "The proof header needs a public jwk",
      );
    }

    let holderKey: Jwk;
    let payload: Readonly<Record<string, unknown>>;

    try {
      // SAFETY: claimed is a JSON object; publicJwk and verifyCompact check its members.
      holderKey = publicJwk(claimed as Jwk);
      ({ payload } = await verifyCompact(
        proof,
        {
          keys: [
            {
              ...holderKey,
              ...(typeof header?.["kid"] === "string"
                ? { kid: header["kid"] }
                : {}),
            },
          ],
        },
        { typ: PROOF_TYP },
      ));
    } catch (error) {
      if (error instanceof JwsError || error instanceof TypeError) {
        return failure(400, "invalid_proof", "The proof does not verify");
      }

      throw error;
    }

    const audience = payload["aud"];

    if (
      !(audience === issuer || (isList(audience) && audience.includes(issuer)))
    ) {
      return failure(400, "invalid_proof", "The proof aud is not the issuer");
    }

    const iat = payload["iat"];

    if (
      typeof iat !== "number" ||
      Math.abs(iat - epochSeconds(clock())) > PROOF_LEEWAY_SECONDS
    ) {
      return failure(400, "invalid_proof", "The proof iat is not current");
    }

    if (
      typeof payload["nonce"] !== "string" ||
      !(await store.takeNonce(await sha256Url(payload["nonce"]), clock()))
    ) {
      return failure(
        400,
        "invalid_nonce",
        "The proof nonce is unknown or used",
      );
    }

    return { holderKey };
  }

  return {
    metadata() {
      return {
        credential_issuer: issuer,
        authorization_servers: [issuer],
        credential_endpoint: options.endpoints.credential,
        nonce_endpoint: options.endpoints.nonce,
        credential_configurations_supported: Object.fromEntries(
          options.sources.map(({ configuration: c }) => [
            c.id,
            {
              format: c.format,
              ...(c.scope === undefined ? {} : { scope: c.scope }),
              ...(c.format === "dc+sd-jwt" ? { vct: c.vct } : {}),
              ...(c.format === "jwt_vc_json"
                ? {
                    credential_definition: {
                      type: ["VerifiableCredential", ...(c.types ?? [])],
                    },
                  }
                : {}),
              cryptographic_binding_methods_supported: ["jwk"],
              credential_signing_alg_values_supported: [signer.alg],
              proof_types_supported: {
                jwt: { proof_signing_alg_values_supported: ["ES256", "EdDSA"] },
              },
              ...(c.display === undefined ? {} : { display: c.display }),
            },
          ]),
        ),
      };
    },

    authorizationServerMetadata() {
      return {
        issuer,
        token_endpoint: options.endpoints.token,
        grant_types_supported: [PRE_AUTHORIZED_GRANT],
        "pre-authorized_grant_anonymous_access_supported": true,
      };
    },

    async createOffer({ configurationId, subject, txCode }) {
      if (!sources.has(configurationId)) {
        throw new TypeError(
          `Unknown credential configuration ${configurationId}`,
        );
      }

      const code = randomUrl(32);
      const expiresAt = inSeconds(options.offerTtl ?? 600);

      await store.saveOffer(await sha256Url(code), {
        configurationId,
        subject,
        expiresAt,
        ...(txCode === undefined
          ? {}
          : { txCodeHash: await sha256Url(txCode) }),
      });

      const offer = {
        credential_issuer: issuer,
        credential_configuration_ids: [configurationId],
        grants: {
          [PRE_AUTHORIZED_GRANT]: {
            "pre-authorized_code": code,
            ...(txCode === undefined
              ? {}
              : {
                  tx_code: {
                    input_mode: /^\d+$/.test(txCode) ? "numeric" : "text",
                    length: txCode.length,
                  },
                }),
          },
        },
      };

      return {
        uri: `openid-credential-offer://?credential_offer=${encodeURIComponent(JSON.stringify(offer))}`,
        offer,
        expiresAt,
      };
    },

    async token(params) {
      if (params["grant_type"] !== PRE_AUTHORIZED_GRANT) {
        return failure(
          400,
          "unsupported_grant_type",
          "Only the pre-authorized code grant is supported",
        );
      }

      const code = params["pre-authorized_code"];

      if (!code) {
        return failure(
          400,
          "invalid_request",
          "pre-authorized_code is required",
        );
      }

      // The offer is burned before tx_code is checked, so a wrong guess ends the code.
      const offer = await store.redeemOffer(await sha256Url(code), clock());

      if (offer === undefined) {
        return failure(
          400,
          "invalid_grant",
          "The pre-authorized code is invalid or expired",
        );
      }

      if (
        offer.txCodeHash !== undefined &&
        (params["tx_code"] === undefined ||
          (await sha256Url(params["tx_code"])) !== offer.txCodeHash)
      ) {
        return failure(400, "invalid_grant", "The tx_code is wrong");
      }

      const ttl = options.tokenTtl ?? 300;
      const accessToken = randomUrl(32);

      await store.saveGrant(await sha256Url(accessToken), {
        configurationId: offer.configurationId,
        subject: offer.subject,
        expiresAt: inSeconds(ttl),
      });

      return {
        status: 200,
        body: {
          access_token: accessToken,
          token_type: "Bearer",
          expires_in: ttl,
        },
        headers: NO_STORE,
      };
    },

    async nonce() {
      const nonce = randomUrl(24);

      await store.saveNonce(
        await sha256Url(nonce),
        inSeconds(options.nonceTtl ?? 300),
      );

      return { status: 200, body: { c_nonce: nonce }, headers: NO_STORE };
    },

    async credential(authorization, body) {
      const token = bearer(authorization);

      if (token === undefined) {
        return unauthorized();
      }

      const requested = isRecord(body)
        ? body["credential_configuration_id"]
        : undefined;

      const source =
        typeof requested === "string" ? sources.get(requested) : undefined;

      if (source === undefined) {
        return failure(
          400,
          "unknown_credential_configuration",
          "credential_configuration_id is unknown",
        );
      }

      const grant = await store.takeGrant(await sha256Url(token), clock());

      if (grant === undefined) {
        return unauthorized();
      }

      const configuration = source.configuration;

      if (grant.configurationId !== configuration.id) {
        return failure(
          400,
          "unknown_credential_configuration",
          "The access token is for another credential",
        );
      }

      // A failure the wallet can retry gives the grant back before it answers.
      const proof = await verifyProof(
        isRecord(body) ? body["proofs"] : undefined,
      );

      if (!("holderKey" in proof)) {
        await store.saveGrant(await sha256Url(token), grant);

        return proof;
      }

      const claims = await source.claims(grant.subject);

      if (claims === undefined) {
        return failure(
          400,
          "invalid_credential_request",
          "The subject no longer qualifies",
        );
      }

      const issuedAt = clock();

      const expiresAt =
        configuration.validFor === undefined
          ? undefined
          : issuedAt
              .toZonedDateTimeISO("UTC")
              .add(configuration.validFor)
              .toInstant();

      const status = await store.allocateStatus(configuration.id);

      let credential: string;

      try {
        credential =
          configuration.format === "dc+sd-jwt"
            ? await issueSdJwt({
                signer,
                issuer,
                vct: configuration.vct ?? configuration.id,
                claims,
                // A source leaves out the claims it has no value for.
                disclosable: (configuration.disclosable ?? []).filter(
                  (name) => name in claims,
                ),
                holderKey: proof.holderKey,
                issuedAt,
                ...(expiresAt === undefined ? {} : { expiresAt }),
                ...(status === undefined ? {} : { status }),
              })
            : await issueJwtVc({
                signer,
                issuer,
                types: configuration.types ?? [],
                subject: {
                  id: `did:jwk:${toBase64Url(JSON.stringify(proof.holderKey))}`,
                  ...claims,
                },
                validFrom: issuedAt,
                holderKey: proof.holderKey,
                ...(expiresAt === undefined ? {} : { validUntil: expiresAt }),
                ...(status === undefined
                  ? {}
                  : { status: bitstringEntry(status.uri, status.idx) }),
              });
      } catch (error) {
        await store.saveGrant(await sha256Url(token), grant);
        throw error;
      }

      await store.recordIssued({
        configurationId: configuration.id,
        subject: grant.subject,
        format: configuration.format,
        issuedAt,
        ...(expiresAt === undefined ? {} : { expiresAt }),
        ...(status === undefined ? {} : { status }),
      });

      return {
        status: 200,
        body: { credentials: [{ credential }] },
        headers: NO_STORE,
      };
    },
  };
}
