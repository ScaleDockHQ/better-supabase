import { describe, expect, it } from "vitest";

import { endStrandedSessions, openSessions } from "../../src/eve/upgrade.ts";
import { memoryStore } from "./memory-store.ts";

function seeded() {
  const store = memoryStore();
  store.seed("old", { eveVersion: "1.0.0" });
  store.seed("new", { eveVersion: "2.0.0" });
  store.seed("done", { eveVersion: "1.0.0", status: "ended" });

  return store;
}

describe("openSessions", () => {
  it("lists the open sessions of other versions", async () => {
    const list = await openSessions({ store: seeded(), notVersion: "2.0.0" });
    expect(list.map((session) => session.sessionId)).toEqual(["old"]);
  });
});

describe("endStrandedSessions", () => {
  it("marks the sessions stranded and cancels their runs", async () => {
    const store = seeded();
    const cancelled: string[] = [];

    const result = await endStrandedSessions({
      store,
      notVersion: "2.0.0",
      cancelRun: (session) => {
        cancelled.push(session.sessionId);

        return Promise.resolve();
      },
    });

    expect(result.ended).toBe(1);
    expect(cancelled).toEqual(["old"]);
    expect(store.statusOf("old")).toBe("stranded");
    expect(store.statusOf("new")).toBe("open");
  });

  it("changes nothing on a dry run", async () => {
    const store = seeded();

    const result = await endStrandedSessions({
      store,
      notVersion: "2.0.0",
      dryRun: true,
    });

    expect(result).toMatchObject({ ended: 0 });
    expect(result.sessions).toHaveLength(1);
    expect(store.statusOf("old")).toBe("open");
  });
});
