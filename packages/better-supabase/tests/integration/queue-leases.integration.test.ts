import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createLeases } from "../../src/blocks/queue/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("queue leases", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("claims, answers busy, takes over an expired lease, completes and releases", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "queue"]);
      await s.service();
      const leases = createLeases(s.sql);

      const first = await leases.claim({ scope: "drain", key: "t1" }).orThrow();
      expect(first.status).toBe("claimed");

      if (first.status !== "claimed") {
        return;
      }

      const second = await leases
        .claim({ scope: "drain", key: "t1" })
        .orThrow();

      expect(second.status).toBe("busy");
      expect(await first.lease.extend(120).orThrow()).toBe(true);

      // A transaction keeps now() fixed, so age the lease by hand.
      await s.client.query(
        "update better_supabase.job_leases set expires_at = now() - interval '1 second'",
      );

      const taken = await leases.claim({ scope: "drain", key: "t1" }).orThrow();
      expect(taken.status).toBe("claimed");

      expect(await first.lease.extend().orThrow()).toBe(false);
      expect(await first.lease.complete().orThrow()).toBe(false);

      if (taken.status !== "claimed") {
        return;
      }

      expect(await taken.lease.complete(60).orThrow()).toBe(true);
      expect(
        (await leases.claim({ scope: "drain", key: "t1" }).orThrow()).status,
      ).toBe("completed");

      const other = await leases.claim({ scope: "drain", key: "t2" }).orThrow();

      expect(other.status).toBe("claimed");

      expect(
        other.status === "claimed" && (await other.lease.release().orThrow()),
      ).toBe(true);

      expect(
        (await leases.claim({ scope: "drain", key: "t2" }).orThrow()).status,
      ).toBe("claimed");
    } finally {
      await s.close();
    }
  });

  it("releases the lease when the function throws", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "queue"]);
      await s.service();
      const leases = createLeases(s.sql);

      const failed = await leases.withLease(
        { scope: "import", key: "file-1", heartbeat: false },
        () => {
          throw new Error("boom");
        },
      );

      expect(failed.ok).toBe(false);

      const again = await leases
        .withLease(
          { scope: "import", key: "file-1", heartbeat: false },
          () => "done",
        )
        .orThrow();

      expect(again).toEqual({ status: "claimed", value: "done" });
    } finally {
      await s.close();
    }
  });
});
