import type { ExtraColumn, ModuleContext } from "../context.ts";

import { raise as raiseWith, sha256Hex } from "../shared.ts";
import { hasPlatformRoles } from "./access-model.ts";

export const PLATFORM_COLUMNS = {
  id: "id",
  email: "email",
  role: "role",
  tokenHash: "token_hash",
  invitedBy: "invited_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
  expiresAt: "expires_at",
  acceptedAt: "accepted_at",
  acceptedBy: "accepted_by",
  declinedAt: "declined_at",
  revokedAt: "revoked_at",
} as const;

export const INVITATION_ERRORS = {
  INVITATION_FORBIDDEN: "42501",
  INVITATION_ROLE_FORBIDDEN: "42501",
  INVITATION_ROLE_UNKNOWN: "23514",
  INVITATION_ALREADY_MEMBER: "23505",
  INVITATION_INVALID: "P0002",
  INVITATION_EXPIRED: "P0002",
  INVITATION_VALIDITY: "22023",
  INVITATION_SIGN_IN: "42501",
  INVITATION_EMAIL_MISMATCH: "42501",
  INVITATION_EMAIL_UNCONFIRMED: "42501",
  INVITATION_SELF: "42501",
  INVITATION_INVITER_REVOKED: "42501",
  INVITATION_SCOPE_UNSUPPORTED: "0A000",
} as const;

export type InvitationError = keyof typeof INVITATION_ERRORS;

/** `raise exception` for `code`, with its SQLSTATE from `INVITATION_ERRORS`. */
export function raise(
  code: InvitationError,
  message: string,
  ...args: string[]
): string {
  return raiseWith(message, INVITATION_ERRORS[code], code, ...args);
}

/**
 * How tokens are stored (`blocks.invitations.options.tokenStorage`): `sha256`
 * (the default) keeps only the hash; `plain` keeps the token itself, for an
 * adopted table whose open invitations hold plain tokens.
 */
export function tokenHash(ctx: ModuleContext, token: string): string {
  const storage = ctx.text("tokenStorage", "sha256");

  if (storage === "plain") {
    return token;
  }

  if (storage !== "sha256") {
    throw new TypeError(
      `blocks.invitations.options.tokenStorage must be "sha256" or "plain", got "${storage}"`,
    );
  }

  return sha256Hex(token);
}

/** A table of invitations: the tenant one, or the platform one. */
export interface InviteTable {
  readonly table: string;
  /** `options.extraColumns`: the tenant table's app columns; none on platform invitations. */
  readonly extras: readonly ExtraColumn[];
  col(logical: string): string;
  has(logical: string): boolean;
  /** ` and <alias>.<tenant> is [not] null` when both kinds share a table. */
  only(alias: string): string;
}

/** Whether platform invitations live in the tenant table, as rows without a tenant. */
function sharesTable(ctx: ModuleContext): boolean {
  return (
    !ctx.manages &&
    ctx.config.tables["platformInvitations"] != null &&
    ctx.table("platformInvitations") === ctx.table("invitations")
  );
}

/** The keys an invitation read returns next to its columns (`inviteJson`). */
const INVITATION_KEYS = [
  "tenant",
  "expires_at",
  "created_at",
  "invited_by",
  "organization",
  "inviter",
  "token",
  "fields",
];

export function tenantTable(ctx: ModuleContext): InviteTable {
  const shared = sharesTable(ctx);

  // Managed tables add prefill only on request (`blocks.invitations.options.prefill`).
  const prefill =
    ctx.has("invitations", "prefill") &&
    (!ctx.manages || ctx.flag("prefill", false));

  return {
    table: ctx.table("invitations"),
    extras: ctx.extraColumns("invitations", INVITATION_KEYS),
    col: (logical) => ctx.col("invitations", logical),
    has: (logical) =>
      logical === "prefill" ? prefill : ctx.has("invitations", logical),
    only: (alias) =>
      shared
        ? ` and ${alias}.${ctx.col("invitations", "tenant")} is not null`
        : "",
  };
}

/**
 * Platform invitations, with the catalog model's platform roles. Managed:
 * their own table. Adopted: `blocks.invitations.tables.platformInvitations`,
 * which may name the tenant table.
 */
export function platformTable(ctx: ModuleContext): InviteTable | undefined {
  if (!hasPlatformRoles(ctx) || !ctx.hasTable("platformInvitations")) {
    return undefined;
  }

  if (!ctx.manages && ctx.config.tables["platformInvitations"] === undefined) {
    return undefined;
  }

  const logical = sharesTable(ctx) ? "invitations" : "platformInvitations";

  // A table shared with tenant invitations has their prefill column.
  const columns = (column: string) =>
    column in PLATFORM_COLUMNS ||
    (logical === "invitations" && column === "prefill");

  return {
    table: ctx.table(logical),
    extras: [],
    col: (column) => ctx.col(logical, column),
    has: (column) => columns(column) && ctx.has(logical, column),
    only: (alias) =>
      logical === "invitations"
        ? ` and ${alias}.${ctx.col("invitations", "tenant")} is null`
        : "",
  };
}

/** A column of the invitation row `alias`, or `fallback` when the table lacks it. */
export function optionalCol(
  t: InviteTable,
  alias: string,
  logical: string,
  fallback: string,
): string {
  return t.has(logical) ? `${alias}.${t.col(logical)}` : fallback;
}

/** `pending`, `accepted`, `declined`, `revoked` or `expired` for row `alias`. */
export function statusOf(t: InviteTable, alias: string): string {
  const c = (logical: string) => `${alias}.${t.col(logical)}`;

  const declined = t.has("declinedAt")
    ? `\n    when ${c("declinedAt")} is not null then 'declined'`
    : "";

  const revoked = t.has("revokedAt")
    ? `\n    when ${c("revokedAt")} is not null then 'revoked'`
    : "";

  return `case
    when ${c("acceptedAt")} is not null then 'accepted'${declined}${revoked}
    when ${c("expiresAt")} < now() then 'expired'
    else 'pending'
  end`;
}

/** Open invitations: not accepted, declined or revoked (expired ones count). */
export function openFilter(t: InviteTable, alias: string): string {
  return ["acceptedAt", "declinedAt", "revokedAt"]
    .filter((logical) => t.has(logical))
    .map((logical) => `${alias}.${t.col(logical)} is null`)
    .join(" and ");
}

/** The catalog role id for a key or id, in `scope`; `expr` itself in other models. */
