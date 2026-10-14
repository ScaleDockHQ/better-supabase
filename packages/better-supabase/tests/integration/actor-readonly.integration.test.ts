import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("read-only actors", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("refuses support, impersonation and a session-only act", async () => {
    const session = await BlockSession.open(pool);
    try {
      await session.install(["actor"]);
      const may = async (act: object | undefined): Promise<boolean> => {
        await session.as(
          { id: crypto.randomUUID(), email: "actor@example.test" },
          act === undefined ? {} : { act },
        );
        return session.value<boolean>("better_supabase.actor_may_write()");
      };
      expect(await may(undefined)).toBe(true);
      expect(await may({ kind: "agent" })).toBe(true);
      expect(await may({ kind: "agent", read_only: true })).toBe(false);
      expect(await may({ kind: "support" })).toBe(false);
      expect(await may({ kind: "impersonation" })).toBe(false);
      expect(await may({ session_id: crypto.randomUUID() })).toBe(false);
      expect(await may({ kind: "support", read_only: false })).toBe(true);
    } finally {
      await session.close();
    }
  });

  it("raises ACTOR_READ_ONLY from a user write", async () => {
    const session = await BlockSession.open(pool);
    try {
      await session.install(["teams"]);
      await session.as(
        { id: crypto.randomUUID(), email: "reader@example.test" },
        { act: { kind: "support" } },
      );
      await expect(
        session.client.query(
          "select better_supabase.create_team($1::uuid, $2::text, $3::text)",
          [crypto.randomUUID(), "Support", ""],
        ),
      ).rejects.toMatchObject({ hint: "ACTOR_READ_ONLY" });
    } finally {
      await session.close();
    }
  });
});
