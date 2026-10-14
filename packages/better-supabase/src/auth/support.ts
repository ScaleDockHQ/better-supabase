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
  /** The approved request this start uses, when the server found one. */
  readonly requestId?: string;
}

/**
 * A request for a support session that waits for a second admin. A start
 * uses an approved request once; `approvedBy` is never `adminId`.
 */
export interface SupportRequest {
  readonly id: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason: string;
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly requestedAt: Temporal.Instant;
  /** An unapproved or unused request is closed after this. */
  readonly expiresAt: Temporal.Instant;
  readonly approvedBy?: string;
  readonly approvedAt?: Temporal.Instant;
  /** The session the approval started. */
  readonly sessionId?: string;
}

export interface SupportRequestInput {
  readonly adminId: string;
  /** The admin's verified claims; the SQL store asks as the admin with them. */
  readonly adminClaims: Readonly<Record<string, unknown>>;
  readonly targetUserId: string;
  readonly reason: string;
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  /**
   * An approver the server's authorization hook already decided, never the
   * admin. The SQL store then records the request approved, over the admin
   * connection.
   */
  readonly approvedBy?: string;
}

/** Who approves a request: with `claims` the store runs as them and decides eligibility itself. */
export interface SupportApprover {
  readonly id: string;
  readonly claims?: SupportCallerClaims;
}

/** What `approvedRequest` looks up. */
export interface SupportApprovalQuery {
  readonly adminId: string;
  readonly targetUserId: string;
  readonly tenant?: string;
  readonly readOnly: boolean;
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
 * SQL module; implement this for another store and check it with
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
  /**
   * Ends every running session past its expiry with `endedBy: "expired"`
   * and returns them. Optional; `support.expire()` fails without it.
   */
  expire?(): Promise<readonly SupportSession[]>;
  /**
   * The store with `namespace` for its time values, unless it was given one
   * itself. Optional; `createServer` calls it with the definition's
   * `temporal`.
   */
  withTemporal?(namespace: typeof Temporal): SupportSessionStore;
  /**
   * Records a request for a session that waits for a second admin.
   * Optional; without it and the two methods below, starts that need an
   * approval are refused.
   */
  request?(input: SupportRequestInput): Promise<SupportRequest>;
  /** A request by id, or `undefined`. */
  getRequest?(requestId: string): Promise<SupportRequest | undefined>;
  /** Approves a request. Rejects when the approver is the requester. */
  approve?(
    requestId: string,
    approver: SupportApprover,
  ): Promise<SupportRequest>;
  /** The approved, unused, unexpired request a start would use, or `undefined`. */
  approvedRequest?(
    query: SupportApprovalQuery,
  ): Promise<SupportRequest | undefined>;
}

interface SupportRequestRow {
  readonly id: string;
  readonly admin_id: string;
  readonly target_user_id: string;
  readonly reason: string;
  readonly read_only: boolean;
  readonly tenant: string | number | null;
  readonly metadata: Record<string, unknown> | null;
  readonly requested_at: string;
  readonly expires_at: string;
  readonly approved_by: string | null;
  readonly approved_at: string | null;
  readonly session_id: string | null;
}

/** A request from the jsonb the `support-sessions` request functions return. */
function supportRequestFromRow(
  row: SupportRequestRow,
  namespace?: typeof Temporal,
): SupportRequest {
  const Instant = (namespace ?? temporal()).Instant;
  return {
    id: row.id,
    adminId: row.admin_id,
    targetUserId: row.target_user_id,
    reason: row.reason,
    readOnly: row.read_only,
    ...(row.tenant === null ? {} : { tenant: String(row.tenant) }),
    metadata: row.metadata ?? {},
    requestedAt: Instant.from(row.requested_at),
    expiresAt: Instant.from(row.expires_at),
    ...(row.approved_by === null ? {} : { approvedBy: row.approved_by }),
    ...(row.approved_at === null
      ? {}
      : { approvedAt: Instant.from(row.approved_at) }),
    ...(row.session_id === null ? {} : { sessionId: row.session_id }),
  };
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

/**
 * A session from the jsonb the `support-sessions` functions return, with
 * `namespace` (else the provided or global Temporal) for its time values.
 */
export function supportSessionFromRow(
  row: SupportRow,
  namespace?: typeof Temporal,
): SupportSession {
  const Instant = (namespace ?? temporal()).Instant;
  const instant = (value: string) => Instant.from(value);
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
  /** `sql.modules.support-sessions.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  /**
   * The Temporal namespace for the sessions' time values, for runtimes
   * without a global one. Defaults to the one `createServer` passes from the
   * definition, then the provided or global Temporal.
   */
  readonly temporal?: typeof Temporal;
}

/**
 * Support sessions in the `support-sessions` SQL module. `start` runs
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
      return supportSessionFromRow(row, options.temporal);
    },
    async get(sessionId, adminId, claims) {
      const row = await one(
        as(claims),
        `select ${fn("active_support_session")}($1, $2) as session`,
        [sessionId, adminId],
      );
      return row ? supportSessionFromRow(row, options.temporal) : undefined;
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
      return rows.map((row) =>
        supportSessionFromRow(row.session, options.temporal),
      );
    },
    async expire() {
      const rows = await postgres.admin.queryRaw<{ session: SupportRow }>(
        `select session from ${fn("expire_support_sessions")}() as session`,
      );
      return rows.map((row) =>
        supportSessionFromRow(row.session, options.temporal),
      );
    },
    withTemporal: (namespace) =>
      options.temporal === undefined
        ? sqlSupportStore(postgres, { ...options, temporal: namespace })
        : sqlSupportStore(postgres, options),
    async claims(targetUserId) {
      const [row] = await postgres.admin.queryRaw<{
        claims: Record<string, unknown>;
      }>(`select ${fn("support_target_claims")}($1) as claims`, [targetUserId]);
      return row?.claims ?? {};
    },
    async request(input) {
      const approved = input.approvedBy !== undefined;
      const row = await oneRequest(
        approved ? postgres.admin : postgres.asUser(input.adminClaims),
        `select ${fn("request_support_session")}($1, $2, $3, $4, $5, $6, $7) as request`,
        [
          input.targetUserId,
          input.reason,
          input.readOnly,
          JSON.stringify(input.metadata),
          input.tenant ?? null,
          input.adminId,
          input.approvedBy ?? null,
        ],
      );
      if (!row) throw new Error("request_support_session returned no request");
      return supportRequestFromRow(row, options.temporal);
    },
    async getRequest(requestId) {
      const row = await oneRequest(
        postgres.admin,
        `select ${fn("support_request")}($1) as request`,
        [requestId],
      );
      return row ? supportRequestFromRow(row, options.temporal) : undefined;
    },
    async approve(requestId, approver) {
      const row = await oneRequest(
        as(approver.claims),
        `select ${fn("approve_support_request")}($1, $2) as request`,
        [requestId, approver.id],
      );
      if (!row) throw new Error("approve_support_request returned no request");
      return supportRequestFromRow(row, options.temporal);
    },
    async approvedRequest(query) {
      const row = await oneRequest(
        postgres.admin,
        `select ${fn("approved_support_request")}($1, $2, $3, $4) as request`,
        [
          query.targetUserId,
          query.tenant ?? null,
          query.readOnly,
          query.adminId,
        ],
      );
      return row ? supportRequestFromRow(row, options.temporal) : undefined;
    },
  };
}

async function oneRequest(
  client: SqlClient,
  text: string,
  params: unknown[],
): Promise<SupportRequestRow | null> {
  const [row] = await client.queryRaw<{ request: SupportRequestRow | null }>(
    text,
    params,
  );
  return row?.request ?? null;
}

/**
 * The claims a support session runs with: the target's, plus `act` naming
 * the admin, the reason and the session (the audit module records all three),
 * marked `kind: "support"` so `actorOf` never reads it as an OAuth client.
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
      kind: "support",
      sub: session.adminId,
      reason: session.reason,
      session_id: session.id,
      read_only: session.readOnly,
    },
  };
}
