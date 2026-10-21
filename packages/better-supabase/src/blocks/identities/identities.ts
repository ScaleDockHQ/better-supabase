import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  IdentityRef,
  IdentityTarget,
  PrincipalByIdentity,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  nullableText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface IdentitiesOptions extends BlockTemporalOptions {
  /**
   * `sqlTransport(postgres.asUser(claims))` for `beginLink`, `list` and
   * `unlink`; a service transport for `redeemLink`, `resolve` and
   * `backfillVerifiedEmails`.
   */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the methods (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Identities>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

/** A one-time code from `beginLink`. Only its SHA-256 is stored. */
export interface LinkCode {
  readonly code: string;
  readonly expiresAt: Temporal.Instant;
}

/** The link `redeemLink` created or found. */
export interface RedeemedLink {
  readonly id: string;
  readonly userId: string;
}

export type IdentitySource = "link" | "verified_email";

/** One of the caller's identities. */
export interface LinkedIdentity {
  readonly id: string;
  readonly kind: IdentityRef["kind"];
  readonly provider: string | null;
  readonly value: string;
  readonly workspace: string | null;
  readonly source: IdentitySource;
  readonly createdAt: Temporal.Instant;
}

/** The `identities` SQL module as typed calls. */
export interface Identities {
  /**
   * Signed-in user: issues a one-time code for the bot or the mail side to
   * redeem.
   */
  readonly beginLink: (
    kind: IdentityRef["kind"],
    provider?: string,
  ) => AsyncResult<LinkCode>;
  /**
   * Service role: binds `identity` to the user who issued `code`. Pass only an
   * identity the platform authenticated, such as the author of a signed Slack
   * event or a DKIM-verified sender.
   */
  readonly redeemLink: (
    code: string,
    identity: IdentityRef,
  ) => AsyncResult<RedeemedLink>;
  /** Service role: the user or contact `identity` is linked to, or `null`. */
  readonly resolve: (
    identity: IdentityRef,
  ) => AsyncResult<IdentityTarget | null>;
  /** The caller's identities, oldest first. */
  readonly list: () => AsyncResult<readonly LinkedIdentity[]>;
  /**
   * Removes one of the caller's identities; `false` when the caller has none
   * with `id`.
   */
  readonly unlink: (id: string) => AsyncResult<boolean>;
  /**
   * Service role: email identities for users confirmed before the module was
   * installed.
   */
  readonly backfillVerifiedEmails: () => AsyncResult<number>;
}

const KINDS: readonly IdentityRef["kind"][] = ["email", "chat"];
const SOURCES: readonly IdentitySource[] = ["link", "verified_email"];

/** The `principal_by_identity` result, or `null` for anything that names no one. */
function targetOf(value: unknown): IdentityTarget | null {
  if (!isRecord(value)) {
    return null;
  }

  if (value["kind"] === "user" && typeof value["userId"] === "string") {
    return { kind: "user", userId: value["userId"] };
  }

  if (value["kind"] === "contact" && typeof value["contactId"] === "string") {
    return { kind: "contact", contactId: value["contactId"] };
  }

  return null;
}

const identityArgs = (
  identity: IdentityRef,
): Readonly<Record<string, unknown>> => ({
  kind: identity.kind,
  provider: identity.provider ?? null,
  value: identity.value,
  workspace: identity.workspace ?? null,
});

export function createIdentities(options: IdentitiesOptions): Identities {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Identities = {
    beginLink: (kind, provider) =>
      call(
        "begin_identity_link",
        { kind, provider: provider ?? null },
        (value) => {
          const row = recordOf(value, "begin_identity_link");

          return {
            code: textOf(row["code"]),
            expiresAt: requiredInstant(row["expires_at"], "expires_at"),
          };
        },
      ),
    redeemLink: (code, identity) =>
      call(
        "redeem_identity_link",
        { code, ...identityArgs(identity) },
        (value) => {
          const row = recordOf(value, "redeem_identity_link");

          return { id: textOf(row["id"]), userId: textOf(row["user_id"]) };
        },
      ),
    resolve: (identity) =>
      call("principal_by_identity", identityArgs(identity), targetOf),
    list: () =>
      call("my_identities", {}, (value) =>
        recordsOf(value, "my_identities").map((row) => ({
          id: textOf(row["id"]),
          kind: enumOrThrow(row["kind"], KINDS, "identity kind"),
          provider: nullableText(row["provider"]),
          value: textOf(row["value"]),
          workspace: nullableText(row["workspace"]),
          source: enumOrThrow(row["source"], SOURCES, "identity source"),
          createdAt: requiredInstant(row["created_at"], "created_at"),
        })),
      ),
    unlink: (id) => call("unlink_identity", { id }, (value) => value === true),
    backfillVerifiedEmails: () =>
      call("backfill_verified_emails", {}, (value) =>
        typeof value === "number" ? value : Number(value),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "identities",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/**
 * A `PrincipalByIdentity` over the `identities` table, for `createServer(bs, {
 * authorization: { identities: { principalByIdentity } } })` or a chat helper's
 * `principalByIdentity` option. `transport` runs as the service role. A
 * database error rejects, so the caller retries instead of treating a linked
 * author as anonymous.
 */
export function identityResolver(
  transport: BlockTransport,
  options: Omit<IdentitiesOptions, "transport"> = {},
): PrincipalByIdentity {
  const identities = createIdentities({ ...options, transport });

  return (identity) => identities.resolve(identity).orThrow();
}

/**
 * `createIdentities({ transport }).beginLink(kind, provider)`, as the signed-in
 * user.
 */
export function beginLink(
  transport: BlockTransport,
  kind: IdentityRef["kind"],
  provider?: string,
): AsyncResult<LinkCode> {
  return createIdentities({ transport }).beginLink(kind, provider);
}

/**
 * `createIdentities({ transport }).redeemLink(code, identity)`, as the service
 * role.
 */
export function redeemLink(
  transport: BlockTransport,
  code: string,
  identity: IdentityRef,
): AsyncResult<RedeemedLink> {
  return createIdentities({ transport }).redeemLink(code, identity);
}
