import type { SqlClient } from "../postgres/executor.ts";
import type { BetterPostgres } from "../postgres/pool.ts";

import { sqlIdent } from "../core/template.ts";
import { temporal } from "../core/temporal-required.ts";

/** The cookie that carries the support session id. */
export const SUPPORT_COOKIE = "bs-support";

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
  /** The admin's session while it is running; `undefined` once ended or expired. */
  get(sessionId: string, adminId: string): Promise<SupportSession | undefined>;
  /** `false` when it was not running. */
  end(sessionId: string, endedBy: SupportEndedBy): Promise<boolean>;
  list(filter?: SupportListFilter): Promise<readonly SupportSession[]>;
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
    async get(sessionId, adminId) {
      const row = await one(
        postgres.admin,
        `select ${fn("active_support_session")}($1, $2) as session`,
        [sessionId, adminId],
      );
      return row ? supportSessionFromRow(row) : undefined;
    },
    async end(sessionId, endedBy) {
      const [row] = await postgres.admin.queryRaw<{ ended: boolean }>(
        `select ${fn("end_support_session")}($1, $2) as ended`,
        [sessionId, endedBy],
      );
      return row?.ended === true;
    },
    async list(filter = {}) {
      const rows = await postgres.admin.queryRaw<{ session: SupportRow }>(
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

export interface SupportCookieOptions {
  /** Defaults to `bs-support`. */
  readonly name?: string;
  /** Defaults to `/`. */
  readonly path?: string;
  /** Defaults to true; set false for plain-HTTP local development. */
  readonly secure?: boolean;
}

/** `Set-Cookie` for a session: HttpOnly, SameSite=Lax, gone when the session expires. */
export function supportCookie(
  session: Pick<SupportSession, "id" | "expiresAt">,
  options: SupportCookieOptions = {},
  now: number = Date.now(),
): string {
  const maxAge = Math.max(
    0,
    Math.floor((session.expiresAt.epochMilliseconds - now) / 1000),
  );
  return cookieLine(options, encodeURIComponent(session.id), maxAge);
}

/** `Set-Cookie` that removes the support cookie. */
export function clearSupportCookie(options: SupportCookieOptions = {}): string {
  return cookieLine(options, "", 0);
}

function cookieLine(
  options: SupportCookieOptions,
  value: string,
  maxAge: number,
): string {
  return [
    `${options.name ?? SUPPORT_COOKIE}=${value}`,
    `Path=${options.path ?? "/"}`,
    `Max-Age=${String(maxAge)}`,
    "HttpOnly",
    "SameSite=Lax",
    ...(options.secure === false ? [] : ["Secure"]),
  ].join("; ");
}

/** The support session id in a `Cookie` header, or `undefined`. */
export function supportCookieValue(
  cookieHeader: string | null,
  name: string = SUPPORT_COOKIE,
): string | undefined {
  if (!cookieHeader) return undefined;
  for (const part of cookieHeader.split(";")) {
    const index = part.indexOf("=");
    if (index === -1 || part.slice(0, index).trim() !== name) continue;
    const value = decodeURIComponent(part.slice(index + 1).trim());
    return value === "" ? undefined : value;
  }
  return undefined;
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
