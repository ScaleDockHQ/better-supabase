import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  postgresStreamStore,
  resumeFromStore,
  sqlTransport,
  teeToStore,
} from "../../src/streams/index.ts";
import { testStreamStore } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

async function text(stream: ReadableStream<string>): Promise<string> {
  let out = "";
  for await (const chunk of stream) out += chunk;
  return out;
}

describe.skipIf(!live)("streams module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("passes the StreamStore kit as the service role", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["streams"]);
      await s.service();
      const store = postgresStreamStore({
        transport: sqlTransport(s.sql),
        wake: "poll",
        pollMs: 10,
      });
      const report = await testStreamStore(store);
      expect(report.checks.every((check) => check.ok)).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("lets only the owner read and cancel, and purges expired streams", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["streams"]);
      const owner = await s.user("owner");
      const other = await s.user("other");
      await s.service();
      const writer = postgresStreamStore({
        transport: sqlTransport(s.sql),
        pollMs: 10,
      });
      const { stream, persisted } = teeToStore(
        writer,
        "chat-1",
        new ReadableStream<string>({
          start(controller) {
            for (const chunk of ["hel", "lo"]) controller.enqueue(chunk);
            controller.close();
          },
        }),
        { owner: owner.id, kind: "chat", flushMs: 1 },
      );
      expect(await text(stream)).toBe("hello");
      expect(await persisted.orThrow()).toBe(2);

      const reader = postgresStreamStore({
        transport: sqlTransport(s.sql),
        pollMs: 10,
      });
      await s.asRole(other);
      expect(await reader.status("chat-1").orThrow()).toBeUndefined();
      expect(await text(reader.read("chat-1"))).toBe("");
      expect(await reader.cancel("chat-1").orThrow()).toBe(false);
      expect(
        await s.hint(
          "select better_supabase.stream_append('chat-1', 2, array['x'])",
        ),
      ).toMatch(/permission denied/);

      await s.asRole(owner);
      const rest = await resumeFromStore(reader, "chat-1", {
        fromIdx: 1,
      }).orThrow();
      expect(rest && (await text(rest))).toBe("lo");
      expect(
        await s.rows(
          "select idx from better_supabase.stream_chunks order by idx",
        ),
      ).toEqual([{ idx: 0 }, { idx: 1 }]);

      await s.service();
      await writer.open("live-1", { owner: owner.id }).orThrow();
      await s.asRole(owner);
      expect(await reader.cancel("live-1").orThrow()).toBe(true);
      await s.service();
      expect(
        (await writer.append("live-1", 0, ["late"]).orThrow()).cancelled,
      ).toBe(true);

      await writer.open("old-1", { ttl: 1 }).orThrow();
      await s.rows(
        "update better_supabase.streams set expires_at = now() - interval '1 minute' where id = 'old-1'",
      );
      expect(await writer.purge().orThrow()).toBe(1);
      expect(await writer.status("old-1").orThrow()).toBeUndefined();
      expect(await writer.status("chat-1").orThrow()).toMatchObject({
        next: 2,
        closed: true,
      });
    } finally {
      await s.close();
    }
  });
});
