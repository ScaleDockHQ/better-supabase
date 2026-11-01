import type { Jwks, JwsAlgorithm } from "../../core/jws.ts";
import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { JwsError, jwksOf, verifyCompact } from "../../core/jws.ts";
import { err, ok } from "../../core/result.ts";

const CLAIM = "https://purl.imsglobal.org/spec/lti/claim/";
const AGS_ENDPOINT = "https://purl.imsglobal.org/spec/lti-ags/claim/endpoint";
const NRPS_CLAIM = "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroles";

const DEEP_LINKING_SETTINGS =
  "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings";

/** The message types a launch verifies. */
export type LtiMessageType = "LtiResourceLinkRequest" | "LtiDeepLinkingRequest";

export interface LtiResourceLink {
  readonly id: string;
  readonly title?: string | undefined;
  readonly description?: string | undefined;
}

export interface LtiContext {
  readonly id: string;
  readonly label?: string | undefined;
  readonly title?: string | undefined;
  readonly types: readonly string[];
}

/** A verified LTI 1.3 launch, its claims read into plain fields. */
export interface LtiLaunch {
  readonly messageType: LtiMessageType;
  readonly issuer: string;
  readonly clientId: string;
  /** The platform's id of the user (`sub`). */
  readonly subject: string;
  readonly deploymentId: string;
  readonly targetLinkUri: string;
  /** Full role URIs, such as `.../membership#Learner`. */
  readonly roles: readonly string[];
  readonly name?: string;
  readonly email?: string;
  readonly context?: LtiContext;
  /** Present for a `LtiResourceLinkRequest`. */
  readonly resourceLink?: LtiResourceLink;
  readonly custom: Readonly<Record<string, string>>;
  /** The Assignment and Grade Services endpoint, when the platform offers it. */
  readonly agsEndpoint?: Readonly<Record<string, unknown>>;
  /** The Names and Role Provisioning Services claim, when offered. */
  readonly namesAndRoles?: Readonly<Record<string, unknown>>;
  /** Present for a `LtiDeepLinkingRequest`. */
  readonly deepLinkingSettings?: Readonly<Record<string, unknown>>;
  readonly nonce: string;
  readonly expiresAt: number;
}

export interface VerifyLtiLaunchOptions {
  /** The platform's public keys, fetched from its JWKS URL by the caller. */
  readonly jwks: Jwks;
  /** The platform's `iss`, from the registration. */
  readonly issuer: string;
  /** The tool's client id at that platform; the `aud` must contain it. */
  readonly clientId: string;
  /**
   * The nonce the tool put in the login redirect and stored with `state`. A
   * launch with another nonce is a replay; the caller also deletes the nonce
   * once the launch passes.
   */
  readonly nonce: string;
  /** Deployment ids the registration accepts. Default: any. */
  readonly deploymentIds?: readonly string[];
  /** The `alg` values accepted. Default `RS256`, which LTI 1.3 requires. */
  readonly algorithms?: readonly JwsAlgorithm[];
  /** The time to check against, in milliseconds. Default now. */
  readonly now?: number;
  /** Clock skew allowed on `exp` and `iat`. Default 60. */
  readonly leewaySeconds?: number;
  /** The longest an id token may be valid for, in seconds. Default 3600. */
  readonly maxLifetimeSeconds?: number;
}

function reject<T>(hint: string, message: string): Result<T> {
  return err(dbError("unauthorized", message, { hint }));
}

function textClaim(
  payload: Readonly<Record<string, unknown>>,
  key: string,
): string | undefined {
  const value = payload[key];

  return typeof value === "string" && value !== "" ? value : undefined;
}

function recordClaim(
  payload: Readonly<Record<string, unknown>>,
  key: string,
): Readonly<Record<string, unknown>> | undefined {
  const value = payload[key];

  return isRecord(value) ? value : undefined;
}

function numberClaim(
  payload: Readonly<Record<string, unknown>>,
  key: string,
): number | undefined {
  const value = payload[key];

  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function audienceOf(payload: Readonly<Record<string, unknown>>): string[] {
  const aud = payload["aud"];

  if (typeof aud === "string") {
    return [aud];
  }

  return Array.isArray(aud)
    ? aud.filter((item): item is string => typeof item === "string")
    : [];
}

function contextOf(
  claim: Readonly<Record<string, unknown>> | undefined,
): LtiContext | undefined {
  const id = claim === undefined ? undefined : textClaim(claim, "id");

  if (claim === undefined || id === undefined) {
    return undefined;
  }

  const types = Array.isArray(claim["type"])
    ? claim["type"].filter((item): item is string => typeof item === "string")
    : [];

  return {
    id,
    ...(textClaim(claim, "label") === undefined
      ? {}
      : { label: textClaim(claim, "label") }),
    ...(textClaim(claim, "title") === undefined
      ? {}
      : { title: textClaim(claim, "title") }),
    types,
  };
}

function customOf(
  claim: Readonly<Record<string, unknown>> | undefined,
): Record<string, string> {
  const custom: Record<string, string> = {};

  for (const [key, value] of Object.entries(claim ?? {})) {
    if (typeof value === "string") {
      custom[key] = value;
    }
  }

  return custom;
}

/**
 * Verifies the `id_token` of an LTI 1.3 launch (IMS LTI 1.3 and the IMS
 * Security Framework 1.1): the RS256 signature against the platform's JWKS,
 * `iss`, `aud` and `azp`, `exp` and `iat`, the nonce, the LTI version, the
 * deployment id and the message's required claims. A failed check returns an
 * `unauthorized` error whose `hint` names it (`LTI_NONCE`, `LTI_AUDIENCE`). It
 * reads no session and stores nothing: the app keeps the login `state` and
 * nonce, and decides which of its users a `subject` maps to.
 */
export async function verifyLtiLaunch(
  idToken: string,
  options: VerifyLtiLaunchOptions,
): Promise<Result<LtiLaunch>> {
  let payload: Readonly<Record<string, unknown>>;

  try {
    ({ payload } = await verifyCompact(idToken, options.jwks, {
      algorithms: options.algorithms ?? ["RS256"],
    }));
  } catch (error) {
    if (error instanceof JwsError) {
      return reject("LTI_SIGNATURE", error.message);
    }

    throw error;
  }

  const now = Math.floor((options.now ?? Date.now()) / 1000);
  const leeway = options.leewaySeconds ?? 60;
  const exp = numberClaim(payload, "exp");
  const iat = numberClaim(payload, "iat");

  if (textClaim(payload, "iss") !== options.issuer) {
    return reject("LTI_ISSUER", "The launch is from another issuer");
  }

  const audience = audienceOf(payload);

  if (!audience.includes(options.clientId)) {
    return reject("LTI_AUDIENCE", "The launch is for another client");
  }

  if (audience.length > 1 && textClaim(payload, "azp") !== options.clientId) {
    return reject("LTI_AUDIENCE", "The authorized party is not this client");
  }

  if (exp === undefined || exp + leeway < now) {
    return reject("LTI_EXPIRED", "The launch token has expired");
  }

  if (iat === undefined || iat - leeway > now) {
    return reject("LTI_ISSUED_AT", "The launch token is issued in the future");
  }

  if (exp - iat > (options.maxLifetimeSeconds ?? 3600)) {
    return reject("LTI_LIFETIME", "The launch token is valid for too long");
  }

  const nonce = textClaim(payload, "nonce");

  if (nonce !== options.nonce) {
    return reject("LTI_NONCE", "The nonce does not match the login request");
  }

  if (textClaim(payload, `${CLAIM}version`) !== "1.3.0") {
    return reject("LTI_VERSION", "Only LTI 1.3.0 launches are supported");
  }

  const messageType = textClaim(payload, `${CLAIM}message_type`);

  if (
    messageType !== "LtiResourceLinkRequest" &&
    messageType !== "LtiDeepLinkingRequest"
  ) {
    return reject("LTI_MESSAGE_TYPE", "The message type is not supported");
  }

  const deploymentId = textClaim(payload, `${CLAIM}deployment_id`);

  if (
    deploymentId === undefined ||
    (options.deploymentIds !== undefined &&
      !options.deploymentIds.includes(deploymentId))
  ) {
    return reject("LTI_DEPLOYMENT", "The deployment is not registered");
  }

  const subject = textClaim(payload, "sub");
  const targetLinkUri = textClaim(payload, `${CLAIM}target_link_uri`);
  const roles = payload[`${CLAIM}roles`];

  if (subject === undefined || targetLinkUri === undefined) {
    return reject("LTI_CLAIMS", "The launch lacks a subject or target link");
  }

  if (!Array.isArray(roles)) {
    return reject("LTI_CLAIMS", "The launch lacks the roles claim");
  }

  const link = recordClaim(payload, `${CLAIM}resource_link`);
  const linkId = link === undefined ? undefined : textClaim(link, "id");

  if (messageType === "LtiResourceLinkRequest" && linkId === undefined) {
    return reject("LTI_CLAIMS", "A resource link launch needs a resource link");
  }

  const settings = recordClaim(payload, DEEP_LINKING_SETTINGS);

  if (messageType === "LtiDeepLinkingRequest" && settings === undefined) {
    return reject("LTI_CLAIMS", "A deep linking launch needs its settings");
  }

  const context = contextOf(recordClaim(payload, `${CLAIM}context`));
  const ags = recordClaim(payload, AGS_ENDPOINT);
  const nrps = recordClaim(payload, NRPS_CLAIM);
  const name = textClaim(payload, "name");
  const email = textClaim(payload, "email");

  return ok({
    messageType,
    issuer: options.issuer,
    clientId: options.clientId,
    subject,
    deploymentId,
    targetLinkUri,
    roles: roles.filter((role): role is string => typeof role === "string"),
    ...(name === undefined ? {} : { name }),
    ...(email === undefined ? {} : { email }),
    ...(context === undefined ? {} : { context }),
    ...(link === undefined || linkId === undefined
      ? {}
      : {
          resourceLink: {
            id: linkId,
            ...(textClaim(link, "title") === undefined
              ? {}
              : { title: textClaim(link, "title") }),
            ...(textClaim(link, "description") === undefined
              ? {}
              : { description: textClaim(link, "description") }),
          },
        }),
    custom: customOf(recordClaim(payload, `${CLAIM}custom`)),
    ...(ags === undefined ? {} : { agsEndpoint: ags }),
    ...(nrps === undefined ? {} : { namesAndRoles: nrps }),
    ...(settings === undefined ? {} : { deepLinkingSettings: settings }),
    nonce,
    expiresAt: exp * 1000,
  });
}

/** The role names an app maps launches to. */
export type LtiRoleName = "Learner" | "Instructor" | "Administrator";

/**
 * Whether the launch's roles hold `role` (IMS LTI 1.3 role vocabulary):
 * institution, system and context role URIs all count, plus the short names
 * some platforms send.
 */
export function ltiHasRole(
  roles: readonly string[],
  role: LtiRoleName,
): boolean {
  return roles.some(
    (value) =>
      value === role ||
      value.endsWith(`#${role}`) ||
      value.endsWith(`/${role}`),
  );
}

/**
 * Reads a platform's JWK Set response, keeping its RSA keys, which `jwksOf`
 * drops by default.
 */
export function ltiJwksOf(value: unknown): Jwks {
  return jwksOf(value, { rsa: true });
}
