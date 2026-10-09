import { describe, expect, it, vi } from "vitest";

import type { CloudEvent, EventSink } from "../../src/events/index.ts";
import type { BetterPostgres } from "../../src/postgres/pool.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { SERVER_EVENT_SOURCE, serverAudit } from "../../src/server/audit.ts";
import { createServer } from "../../src/server/server.ts";
import { supportSessions } from "../../src/server/support.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { memorySupportStore } from "../fixtures/support-store.ts";

const env = {
  url: "https://abcdefghijklmnopqrst.supabase.co",
  publishableKey: "sb_publishable_test",
  secretKey: "sb_secret_test",
  jwksUrl: new URL(
    "https://abcdefghijklmnopqrst.supabase.co/auth/v1/.well-known/jwks.json",
  ),
};
const USER = "6f1f5b8e-2c1d-4a3b-9e7f-0a1b2c3d4e5f";
const ADMIN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

function setup(sink: EventSink) {
  const fake = fakeSql([[/delete from auth\.sessions/, [{ ended: 2 }]]]);
  // SAFETY: the server only calls admin.queryRaw and executorFor here.
  const postgres = {
    admin: fake.sql,
    anon: fake.sql,
    executorFor: () => postgresExecutor(fake.sql),
  } as unknown as BetterPostgres;
  const betterSupabase = defineSupabase(schema);
  const server = createServer(betterSupabase, {
    env,
    postgres,
    support: supportSessions({ store: memorySupportStore() }),
    audit: sink,
  });
  return { server, betterSupabase };
}

describe("the server's audit sink", () => {
  it("records ended sessions and support denials as CloudEvents", async () => {
    const sent: CloudEvent[] = [];
    const { server } = setup({ send: (events) => void sent.push(...events) });
    expect((await server.endSessions(USER).orThrow()).ended).toBe(2);
    await server.support.start(
      {
        kind: "user",
        token: "t",
        claims: { sub: ADMIN, role: "authenticated" },
        user: { id: ADMIN, role: "authenticated" },
        source: "bearer",
        expiresAt: null,
      },
      { targetUserId: USER },
    );
    await server.events.settled();
    expect(sent.map((event) => event.type)).toEqual([
      "dev.better-supabase.account.sessions_ended",
      "dev.better-supabase.support.denied",
    ]);
    expect(sent[0]).toMatchObject({
      source: SERVER_EVENT_SOURCE,
      subject: `users/${USER}`,
      data: { userId: USER, ended: 2 },
    });
    expect(sent[1]?.data).toMatchObject({ denial: "policy", actorId: ADMIN });
  });

  it("never fails the action when the sink throws", async () => {
    const { server, betterSupabase } = setup({
      send: () => {
        throw new Error("down");
      },
    });
    const error = vi
      .spyOn(betterSupabase.events.logger, "error")
      .mockImplementation(() => undefined);
    expect((await server.endSessions(USER)).ok).toBe(true);
    await server.events.settled();
    expect(error).toHaveBeenCalledWith("audit sink failed", expect.anything());
  });

  it("does nothing without a sink", () => {
    const betterSupabase = defineSupabase(schema);
    const on = vi.spyOn(betterSupabase.events, "on");
    serverAudit(betterSupabase, undefined).account("account.deleted", USER, {});
    expect(on).not.toHaveBeenCalled();
  });
});
