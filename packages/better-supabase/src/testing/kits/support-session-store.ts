import type { SupportSessionStore } from "../../auth/support.ts";

import {
  conform,
  expect,
  same,
  type ConformanceReport,
} from "../conformance.ts";
import { hasName } from "./executor.ts";

export interface TestSupportSessionStoreOptions {
  /** A user who may start support sessions in the store. */
  readonly admin: {
    readonly id: string;
    readonly claims: Readonly<Record<string, unknown>>;
  };
  /** Two other users the admin may view the app as. */
  readonly targets: readonly [string, string];
}

/**
 * Proves a `SupportSessionStore` starts sessions with the input it was given,
 * shows a running session only to its admin, ends the admin's previous session
 * on start, ends a session once, lists sessions and, with `expire`, leaves
 * running sessions alone. It writes sessions to the store; they are all ended
 * when it returns.
 */
export function testSupportSessionStore(
  store: SupportSessionStore,
  options: TestSupportSessionStoreOptions,
): Promise<ConformanceReport> {
  const { admin } = options;
  const [first, second] = options.targets;

  const start = (targetUserId: string) =>
    store.start({
      adminId: admin.id,
      adminClaims: admin.claims,
      targetUserId,
      reason: "conformance",
      ttlSeconds: 600,
      readOnly: true,
      metadata: { ticket: "T-1" },
    });

  return conform(`SupportSessionStore "${store.name}"`, [
    hasName(store),
    [
      "has apiVersion 1",
      () => {
        const version: unknown = store.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "starts a session with its input and shows it to its admin only",
      async () => {
        const session = await start(first);

        try {
          expect(session.id.length > 0, "start must return an id");
          expect(session.adminId === admin.id, "adminId must round-trip");
          expect(
            session.targetUserId === first,
            "targetUserId must round-trip",
          );
          expect(session.reason === "conformance", "reason must round-trip");
          expect(session.readOnly, "readOnly must round-trip");
          expect(
            same(session.metadata, { ticket: "T-1" }),
            "metadata must round-trip",
          );

          const seconds =
            (session.expiresAt.epochMilliseconds -
              session.startedAt.epochMilliseconds) /
            1000;

          expect(
            Math.abs(seconds - 600) < 5,
            "expiresAt must be ttlSeconds after startedAt",
          );
          const found = await store.get(session.id, admin.id);
          expect(
            found?.id === session.id,
            "get must return the running session",
          );
          expect(
            (await store.get(session.id, first)) === undefined,
            "get must hide a session from anyone but its admin",
          );
        } finally {
          await store.end(session.id, "admin");
        }
      },
    ],
    [
      "ends the admin's previous session on start",
      async () => {
        const older = await start(first);
        const newer = await start(second);

        try {
          expect(
            (await store.get(older.id, admin.id)) === undefined,
            "starting a session must end the admin's previous one",
          );
          expect(
            (await store.get(newer.id, admin.id))?.id === newer.id,
            "the new session must be running",
          );
        } finally {
          await store.end(newer.id, "admin");
        }
      },
    ],
    [
      "ends a session once and lists it",
      async () => {
        const session = await start(first);
        expect(await store.end(session.id, "admin"), "end must return true");
        expect(
          !(await store.end(session.id, "admin")),
          "ending an ended session must return false",
        );
        expect(
          (await store.get(session.id, admin.id)) === undefined,
          "get must not return an ended session",
        );
        const listed = await store.list({ adminId: admin.id, active: false });
        const entry = listed.find((item) => item.id === session.id);
        expect(entry, "list must include the ended session");
        expect(entry.endedAt !== undefined, "an ended session has endedAt");
        const running = await store.list({ adminId: admin.id, active: true });
        expect(
          running.every((item) => item.id !== session.id),
          "list({ active: true }) must leave out ended sessions",
        );
      },
    ],
    [
      "expires only sessions past their expiry, when it has expire",
      async () => {
        if (!store.expire) {
          return;
        }

        const session = await start(first);

        try {
          const expired = await store.expire();
          expect(
            expired.every((item) => item.id !== session.id),
            "expire must leave a running session alone",
          );
          expect(
            expired.every((item) => item.endedBy === "expired"),
            "expire must end sessions with endedBy expired",
          );
          expect(
            (await store.get(session.id, admin.id))?.id === session.id,
            "the running session must still be running after expire",
          );
        } finally {
          await store.end(session.id, "admin");
        }
      },
    ],
  ]);
}
