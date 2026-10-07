import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
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
  return `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${INVITATION_ERRORS[code]}', hint = '${code}';`;
}

/**
 * How tokens are stored (`sql.modules.invitations.options.tokenStorage`): `sha256`
 * (the default) keeps only the hash; `plain` keeps the token itself, for an
 * adopted table whose open invitations hold plain tokens.
 */
export function tokenHash(ctx: ModuleContext, token: string): string {
  const storage = ctx.text("tokenStorage", "sha256");
  if (storage === "plain") return token;
  if (storage !== "sha256") {
    throw new TypeError(
      `sql.modules.invitations.options.tokenStorage must be "sha256" or "plain", got "${storage}"`,
    );
  }
  return `encode(extensions.digest(${token}, 'sha256'), 'hex')`;
}

/** A table of invitations: the tenant one, or the platform one. */
export interface InviteTable {
  readonly table: string;
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

export function tenantTable(ctx: ModuleContext): InviteTable {
  const shared = sharesTable(ctx);
  // Managed tables add prefill only on request (`sql.modules.invitations.options.prefill`).
  const prefill =
    ctx.has("invitations", "prefill") &&
    (!ctx.manages || ctx.flag("prefill", false));
  return {
    table: ctx.table("invitations"),
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
 * their own table. Adopted: `sql.modules.invitations.tables.platformInvitations`,
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
  return {
    table: ctx.table(logical),
    col: (column) => ctx.col(logical, column),
    has: (column) => column in PLATFORM_COLUMNS && ctx.has(logical, column),
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
