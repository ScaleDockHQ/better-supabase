import type {
  EveOpenSession,
  EveSessionLease,
  EveSessionStatus,
  EveSessionStore,
} from "../../src/eve/store.ts";

interface Row {
  cursor: number;
  status: EveSessionStatus;
  leaseId: string | undefined;
  tenantId: string | undefined;
  principalId: string | undefined;
  principalKind: string | undefined;
  chatId: string | undefined;
  behind: boolean;
  eveVersion: string | undefined;
}

/** An in-memory `EveSessionStore` for tests, with a few inspection helpers. */
export interface MemoryEveStore extends EveSessionStore {
  readonly wakes: string[];
  cursorOf(sessionId: string): number | undefined;
  statusOf(sessionId: string): EveSessionStatus | undefined;
  rewind(sessionId: string): void;
  seed(
    sessionId: string,
    row: { readonly eveVersion?: string; readonly status?: EveSessionStatus },
  ): void;
}

export function memoryStore(): MemoryEveStore {
  const rows = new Map<string, Row>();
  const wakes: string[] = [];
  let counter = 0;

  const row = (sessionId: string): Row => {
    const found = rows.get(sessionId);

    if (found !== undefined) {
      return found;
    }

    const created: Row = {
      cursor: 0,
      status: "open",
      leaseId: undefined,
      tenantId: undefined,
      principalId: undefined,
      principalKind: undefined,
      chatId: undefined,
      behind: false,
      eveVersion: undefined,
    };

    rows.set(sessionId, created);

    return created;
  };

  return {
    wakes,
    cursorOf: (id) => rows.get(id)?.cursor,
    statusOf: (id) => rows.get(id)?.status,
    rewind(id) {
      row(id).cursor = 0;
    },
    seed(id, input) {
      const target = row(id);
      target.eveVersion = input.eveVersion;
      target.status = input.status ?? "open";
    },
    wake(sessionId) {
      row(sessionId).behind = true;
      wakes.push(sessionId);

      return Promise.resolve();
    },
    lease(sessionId) {
      const target = row(sessionId);

      if (target.leaseId !== undefined) {
        return Promise.resolve(undefined);
      }

      counter += 1;
      target.leaseId = `lease-${counter}`;

      const lease: EveSessionLease = {
        sessionId,
        tenantId: target.tenantId,
        principalKind: target.principalKind,
        principalId: target.principalId,
        eveVersion: target.eveVersion,
        chatId: target.chatId,
        recordType: undefined,
        recordId: undefined,
        runId: `run-${sessionId}`,
        cursor: target.cursor,
        status: target.status,
        leaseId: target.leaseId,
      };

      return Promise.resolve(lease);
    },
    commit(input) {
      const target = row(input.sessionId);

      if (target.leaseId !== input.leaseId) {
        return Promise.resolve(false);
      }

      target.cursor = Math.max(target.cursor, input.cursor);
      target.tenantId = input.tenantId ?? target.tenantId;
      target.principalId = input.principalId ?? target.principalId;
      target.principalKind = input.principalKind ?? target.principalKind;
      target.chatId = input.chatId ?? target.chatId;
      target.status = input.status ?? target.status;
      target.leaseId = undefined;
      target.behind = false;

      return Promise.resolve(true);
    },
    release(sessionId, leaseId) {
      const target = row(sessionId);

      if (target.leaseId !== leaseId) {
        return Promise.resolve(false);
      }

      target.leaseId = undefined;

      return Promise.resolve(true);
    },
    behind() {
      return Promise.resolve(
        [...rows.entries()]
          .filter(([, value]) => value.behind && value.status === "open")
          .map(([id]) => id),
      );
    },
    open(options = {}) {
      const list: EveOpenSession[] = [...rows.entries()]
        .filter(
          ([, value]) =>
            value.status === "open" &&
            (options.notVersion === undefined ||
              value.eveVersion !== options.notVersion),
        )
        .map(([sessionId, value]) => ({
          sessionId,
          eveVersion: value.eveVersion,
          tenantId: value.tenantId,
          principalId: value.principalId,
          chatId: value.chatId,
          runId: undefined,
        }));

      return Promise.resolve(list);
    },
    mark(sessionId, status) {
      const target = row(sessionId);
      target.status = status;
      target.behind = true;

      return Promise.resolve(true);
    },
  };
}
