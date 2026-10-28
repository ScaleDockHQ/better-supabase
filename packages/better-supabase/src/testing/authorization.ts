import type { JWTClaims } from "@supabase/server";

import type { SessionSnapshot } from "../auth/snapshot.ts";
import type {
  AuthorizationPurpose,
  AuthorizationRequest,
  AuthorizationResource,
} from "../core/authorizer.ts";
import type { Actor, RequestContext } from "../core/plugin.ts";

import { snapshotOf } from "../auth/snapshot.ts";
import { requestOf } from "../core/authorizer.ts";
import { toBase64Url } from "../core/base64.ts";

type JsonObject = Readonly<Record<string, unknown>>;

/** What `authorizationRequest` builds a request from. */
export interface AuthorizationRequestInput<Ref> {
  readonly action: Ref;
  /**
   * The verified claims. `sub` is the subject id and `role` its Postgres role;
   * leave both `claims` and `subject` out for an anonymous request.
   */
  readonly claims?: JsonObject;
  /** The actor, when it isn't the user in `claims.sub`. */
  readonly subject?: Actor;
  /** Defaults to `{ type: "test" }`. */
  readonly resource?: AuthorizationResource;
  readonly context?: AuthorizationPurpose & {
    readonly tenant?: string;
    readonly requestId?: string;
    readonly approval?: string;
  };
}

function actorFrom(claims: JsonObject | undefined): Actor | undefined {
  const sub = claims?.["sub"];

  if (typeof sub !== "string" || sub === "") {
    return undefined;
  }

  const role = claims?.["role"];

  return {
    id: sub,
    kind: "user",
    role: typeof role === "string" ? role : "authenticated",
  };
}

/**
 * The `AuthorizationRequest` better-supabase sends an authorizer for this
 * input, built through the same `requestOf` the server and repositories use, so
 * tests see the subject, claims and context fields an authorizer gets.
 */
export function authorizationRequest<Ref>(
  input: AuthorizationRequestInput<Ref>,
): AuthorizationRequest<Ref> {
  const { intent, operation, tenant, requestId, approval } =
    input.context ?? {};

  const actor = input.subject ?? actorFrom(input.claims);

  const context: RequestContext = {
    ...(actor ? { actor } : {}),
    ...(input.claims ? { claims: input.claims } : {}),
    ...(tenant === undefined ? {} : { tenant }),
    ...(requestId === undefined ? {} : { requestId }),
    ...(approval === undefined ? {} : { approval }),
  };

  const built = requestOf(context, {
    ...(intent === undefined ? {} : { intent }),
    ...(operation === undefined ? {} : { operation }),
  });

  return {
    subject: built.subject,
    action: input.action,
    resource: input.resource ?? { type: "test" },
    context: built.context,
  };
}

/** What `sessionSnapshot` builds a snapshot from. */
export interface SessionSnapshotInput {
  /** The token's claims; `sub` is required. */
  readonly claims: JsonObject;
}

/**
 * A `SessionSnapshot` for `claims`, built through the same `snapshotOf` the
 * server uses. The access token is an unsigned JWT that carries the claims;
 * nothing verifies it.
 */
export function sessionSnapshot(
  input: SessionSnapshotInput,
): SessionSnapshot<JsonObject> {
  const { claims } = input;
  const sub = claims["sub"];

  if (typeof sub !== "string" || sub === "") {
    throw new TypeError("sessionSnapshot needs claims.sub");
  }

  const exp = claims["exp"];
  const role = claims["role"];

  const token = [
    toBase64Url(JSON.stringify({ alg: "none", typ: "JWT" })),
    toBase64Url(JSON.stringify(claims)),
    "",
  ].join(".");

  const snapshot = snapshotOf<JsonObject, unknown>({
    kind: "user",
    token,
    // SAFETY: the snapshot copies the claims; nothing reads JWTClaims fields from them.
    claims: claims as JWTClaims & JsonObject,
    user: { id: sub, role: typeof role === "string" ? role : "authenticated" },
    source: "bearer",
    expiresAt: typeof exp === "number" ? exp : null,
  });

  if (!snapshot) {
    throw new TypeError("sessionSnapshot built no snapshot");
  }

  return snapshot;
}
