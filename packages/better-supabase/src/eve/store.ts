/** The status of a session in `workflow.eve_sessions`. */
export type EveSessionStatus =
  | "open"
  | "ended"
  | "failed"
  | "cancelled"
  | "stranded";

/** A session row a sync job holds the lease on. */
export interface EveSessionLease {
  readonly sessionId: string;
  readonly tenantId: string | undefined;
  readonly principalKind: string | undefined;
  readonly principalId: string | undefined;
  readonly eveVersion: string | undefined;
  readonly chatId: string | undefined;
  readonly recordType: string | undefined;
  readonly recordId: string | undefined;
  /** The id of the session's newest eve run. */
  readonly runId: string | undefined;
  /** The next line of the session stream to read. */
  readonly cursor: number;
  readonly status: EveSessionStatus;
  /** Pass it to `commit` and `release`. */
  readonly leaseId: string;
}

/** What `commit` stores once a pass has written its facts. */
export interface EveSessionCommit {
  readonly sessionId: string;
  readonly leaseId: string;
  /** The next line to read. It never moves back. */
  readonly cursor: number;
  readonly tenantId?: string | undefined;
  readonly principalKind?: string | undefined;
  readonly principalId?: string | undefined;
  readonly chatId?: string | undefined;
  readonly recordType?: string | undefined;
  readonly recordId?: string | undefined;
  readonly status?: EveSessionStatus | undefined;
}

/** An open session, as `open` lists it. */
export interface EveOpenSession {
  readonly sessionId: string;
  readonly eveVersion: string | undefined;
  readonly tenantId: string | undefined;
  readonly principalId: string | undefined;
  readonly chatId: string | undefined;
  readonly runId: string | undefined;
}

export interface EveBehindOptions {
  /**
   * Open sessions not synced for this long count as behind. Default `5
   * minutes`.
   */
  readonly olderThan?: string;
  /** 1 to 1000, default 100. */
  readonly limit?: number;
}

export interface EveOpenOptions {
  /** Leaves out the sessions that run this eve version. */
  readonly notVersion?: string;
  readonly tenantId?: string;
  /** 1 to 1000, default 100. */
  readonly limit?: number;
}

/**
 * The `eve_session_*` functions of the `workflow-sdk` module, over the World's
 * service connection. `createSupabaseWorld()` returns it as `eveSessions`.
 */
export interface EveSessionStore {
  /** Marks the session behind and queues its debounced sync job. */
  wake(sessionId: string, delaySeconds?: number): Promise<void>;
  /** Takes the lease, or resolves `undefined` while another job holds it. */
  lease(
    sessionId: string,
    leaseSeconds?: number,
  ): Promise<EveSessionLease | undefined>;
  /** Stores the cursor and frees the lease; `false` when the lease expired. */
  commit(input: EveSessionCommit): Promise<boolean>;
  /** Frees the lease without moving the cursor. */
  release(sessionId: string, leaseId: string): Promise<boolean>;
  /** The ids of the sessions a sync job has not caught up with. */
  behind(options?: EveBehindOptions): Promise<readonly string[]>;
  /** The open sessions, oldest first. */
  open(options?: EveOpenOptions): Promise<readonly EveOpenSession[]>;
  /** Sets the status, such as `stranded`, and queues a sync. */
  mark(sessionId: string, status: EveSessionStatus): Promise<boolean>;
}

type Call = <T>(fn: string, args: readonly unknown[]) => Promise<T[]>;

const STATUSES: readonly EveSessionStatus[] = [
  "open",
  "ended",
  "failed",
  "cancelled",
  "stranded",
];

function statusOf(value: unknown): EveSessionStatus {
  const found = STATUSES.find((status) => status === value);

  if (found === undefined) {
    throw new TypeError(`eve: unknown session status ${String(value)}`);
  }

  return found;
}

const text = (value: string | null | undefined): string | undefined =>
  value ?? undefined;

interface LeaseRow {
  readonly session_id: string;
  readonly tenant_id: string | null;
  readonly principal_kind: string | null;
  readonly principal_id: string | null;
  readonly eve_version: string | null;
  readonly chat_id: string | null;
  readonly record_type: string | null;
  readonly record_id: string | null;
  readonly run_id: string | null;
  readonly read_cursor: string | number;
  readonly status: string;
  readonly lease_id: string;
}

interface OpenRow {
  readonly session_id: string;
  readonly eve_version: string | null;
  readonly tenant_id: string | null;
  readonly principal_id: string | null;
  readonly chat_id: string | null;
  readonly run_id: string | null;
}

/** The session store over a function caller (the World's pool). */
export function createEveSessionStore(call: Call): EveSessionStore {
  return {
    async wake(sessionId, delaySeconds = 2) {
      await call("eve_session_wake", [sessionId, delaySeconds]);
    },
    async lease(sessionId, leaseSeconds = 60) {
      const [row] = await call<LeaseRow>("eve_session_lease", [
        sessionId,
        leaseSeconds,
      ]);

      if (row === undefined) {
        return;
      }

      return {
        sessionId: row.session_id,
        tenantId: text(row.tenant_id),
        principalKind: text(row.principal_kind),
        principalId: text(row.principal_id),
        eveVersion: text(row.eve_version),
        chatId: text(row.chat_id),
        recordType: text(row.record_type),
        recordId: text(row.record_id),
        runId: text(row.run_id),
        cursor: Number(row.read_cursor),
        status: statusOf(row.status),
        leaseId: row.lease_id,
      };
    },
    async commit(input) {
      const [row] = await call<{ eve_session_commit: boolean }>(
        "eve_session_commit",
        [
          input.sessionId,
          input.leaseId,
          input.cursor,
          input.tenantId ?? null,
          input.principalKind ?? null,
          input.principalId ?? null,
          input.chatId ?? null,
          input.recordType ?? null,
          input.recordId ?? null,
          input.status ?? null,
        ],
      );

      return row?.eve_session_commit === true;
    },
    async release(sessionId, leaseId) {
      const [row] = await call<{ eve_session_release: boolean | null }>(
        "eve_session_release",
        [sessionId, leaseId],
      );

      return row?.eve_session_release === true;
    },
    async behind(options = {}) {
      const rows = await call<{ session_id: string }>("eve_sessions_behind", [
        options.olderThan ?? "5 minutes",
        options.limit ?? 100,
      ]);

      return rows.map((row) => row.session_id);
    },
    async open(options = {}) {
      const rows = await call<OpenRow>("eve_open_sessions", [
        options.notVersion ?? null,
        options.tenantId ?? null,
        options.limit ?? 100,
      ]);

      return rows.map((row) => ({
        sessionId: row.session_id,
        eveVersion: text(row.eve_version),
        tenantId: text(row.tenant_id),
        principalId: text(row.principal_id),
        chatId: text(row.chat_id),
        runId: text(row.run_id),
      }));
    },
    async mark(sessionId, status) {
      const [row] = await call<{ eve_session_mark: boolean }>(
        "eve_session_mark",
        [sessionId, status],
      );

      return row?.eve_session_mark === true;
    },
  };
}
