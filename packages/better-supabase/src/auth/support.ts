import type { SqlClient } from "../postgres/executor.ts";
import type { BetterPostgres } from "../postgres/pool.ts";

import { sqlIdent } from "../core/template.ts";
import { temporal } from "../core/temporal-required.ts";

export type SupportEndedBy = "admin" | "expired" | "revoked";

/** A support session: a platform admin viewing the app as `targetUserId`. */
export interface SupportSession {
  readonly id: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason: string;
  /** Writes fail while it is true (`begin read only`). */
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly startedAt: Temporal.Instant;
  readonly expiresAt: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly endedBy?: SupportEndedBy;
  /** App data, such as a ticket id. */
  readonly metadata: Readonly<Record<string, unknown>>;
}

export interface SupportStartInput {
  readonly adminId: string;
  /**
   * The admin's verified claims. The SQL store runs `start_support_session`
   * with them, so `is_platform()` checks the admin in the database too.
   */
  readonly adminClaims: Readonly<Record<string, unknown>>;
  readonly targetUserId: string;
  readonly reason: string;
  readonly ttlSeconds: number;
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
}

/** A caller's verified claims, which the store runs a call with. */
export type SupportCallerClaims = Readonly<Record<string, unknown>>;

export interface SupportListFilter {
  readonly adminId?: string;
  readonly targetUserId?: string;
  /** `true`: running sessions only; `false`: ended or expired ones only. */
  readonly active?: boolean;
  /** Defaults to 50. */
  readonly limit?: number;
}

/**
 * Where support sessions live. `sqlSupportStore` uses the `support-sessions`
 * SQL kit module; implement this for another store and check it with
 * `testSupportSessionStore` from `better-supabase/testing`.
 */
export interface SupportSessionStore {
  readonly apiVersion: 1;
  readonly name: string;
  /** Starts a session and ends the admin's previous one. Rejects when the store refuses. */
  start(input: SupportStartInput): Promise<SupportSession>;
  /**
   * The admin's session while it is running; `undefined` once ended or
   * expired. With the admin's `claims`, the store also checks that the admin
   * may still start sessions.
   */
  get(
    sessionId: string,
    adminId: string,
    claims?: SupportCallerClaims,
  ): Promise<SupportSession | undefined>;
  /**
   * `false` when it was not running. With `claims`, it runs as that caller:
   * the session's admin, or staff with the revoke permission.
   */
  end(
    sessionId: string,
    endedBy: SupportEndedBy,
    claims?: SupportCallerClaims,
  ): Promise<boolean>;
  /** With `claims`, only what that caller may view. */
  list(
    filter?: SupportListFilter,
    claims?: SupportCallerClaims,
  ): Promise<readonly SupportSession[]>;
  /** The claims `targetUserId` would get, when the store can build them. */
  claims?(targetUserId: string): Promise<Readonly<Record<string, unknown>>>;
}

interface SupportRow {
  readonly id: string;
  readonly admin_id: string;
  readonly target_user_id: string;
  readonly reason: string;
  readonly read_only: boolean | null;
  readonly tenant: string | number | null;
  readonly started_at: string;
  readonly expires_at: string;
  readonly ended_at: string | null;
  readonly ended_by: SupportEndedBy | null;
  readonly metadata: Record<string, unknown> | null;
}

/** A session from the jsonb the `support-sessions` functions return. */
export function supportSessionFromRow(row: SupportRow): SupportSession {
  const instant = (value: string) => temporal().Instant.from(value);
  return {
    id: row.id,
    adminId: row.admin_id,
    targetUserId: row.target_user_id,
    reason: row.reason,
    readOnly: row.read_only ?? true,
    ...(row.tenant === null ? {} : { tenant: String(row.tenant) }),
    startedAt: instant(row.started_at),
    expiresAt: instant(row.expires_at),
    ...(row.ended_at === null ? {} : { endedAt: instant(row.ended_at) }),
    ...(row.ended_by === null ? {} : { endedBy: row.ended_by }),
    metadata: row.metadata ?? {},
  };
}

export interface SqlSupportStoreOptions {
  /** `kits.support-sessions.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
}

/**
 * Support sessions in the `support-sessions` SQL kit module. `start` runs
 * as the admin, so the module's `is_platform()` gate applies; the reads run
 * on the admin connection.
 */
export function sqlSupportStore(
  postgres: Pick<BetterPostgres, "admin" | "asUser">,
  options: SqlSupportStoreOptions = {},
): SupportSessionStore {
  const fn = (name: string) =>
    `${sqlIdent(options.schema ?? "better_supabase")}.${sqlIdent(name)}`;
  const as = (claims: SupportCallerClaims | undefined): SqlClient =>
    claims ? postgres.asUser(claims) : postgres.admin;
  const one = async (
    client: SqlClient,
    text: string,
    params: unknown[],
  ): Promise<SupportRow | null> => {
    const [row] = await client.queryRaw<{ session: SupportRow | null }>(
      text,
      params,
    );
    return row?.session ?? null;
  };
  return {
    apiVersion: 1,
    name: "sql",
    async start(input) {
      const row = await one(
        postgres.asUser(input.adminClaims),
        `select ${fn("start_support_session")}($1, $2, $3::interval, $4, $5, $6, $7) as session`,
        [
          input.targetUserId,
          input.reason,
          `${String(input.ttlSeconds)} seconds`,
          input.readOnly,
          JSON.stringify(input.metadata),
          input.tenant ?? null,
          input.adminId,
        ],
      );
      if (!row) throw new Error("start_support_session returned no session");
      return supportSessionFromRow(row);
    },
    async get(sessionId, adminId, claims) {
      const row = await one(
        as(claims),
        `select ${fn("active_support_session")}($1, $2) as session`,
        [sessionId, adminId],
      );
      return row ? supportSessionFromRow(row) : undefined;
    },
    async end(sessionId, endedBy, claims) {
      const [row] = await as(claims).queryRaw<{ ended: boolean }>(
        `select ${fn("end_support_session")}($1, $2) as ended`,
        [sessionId, endedBy],
      );
      return row?.ended === true;
    },
    async list(filter = {}, claims) {
      const rows = await as(claims).queryRaw<{ session: SupportRow }>(
        `select session from ${fn("list_support_sessions")}($1, $2, $3, $4) as session`,
        [
          filter.adminId ?? null,
          filter.targetUserId ?? null,
          filter.active ?? null,
          filter.limit ?? 50,
        ],
      );
      return rows.map((row) => supportSessionFromRow(row.session));
    },
    async claims(targetUserId) {
      const [row] = await postgres.admin.queryRaw<{
        claims: Record<string, unknown>;
      }>(`select ${fn("support_target_claims")}($1) as claims`, [targetUserId]);
      return row?.claims ?? {};
    },
  };
}

/**
 * The claims a support session runs with: the target's, plus `act` naming
 * the admin, the reason and the session (the audit module records all three).
 * `role` falls back to `authenticated`; the admin's claims never leak in.
 */
export function supportClaims(
  session: Pick<
    SupportSession,
    "id" | "adminId" | "targetUserId" | "reason" | "readOnly"
  >,
  target: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const role = target["role"];
  return {
    ...target,
    sub: session.targetUserId,
    role: typeof role === "string" && role !== "" ? role : "authenticated",
    act: {
      sub: session.adminId,
      reason: session.reason,
      session_id: session.id,
      read_only: session.readOnly,
    },
  };
}
