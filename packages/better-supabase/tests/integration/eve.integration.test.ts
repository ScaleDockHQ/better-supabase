import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/blocks/ai-chat/index.ts";

import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createMemory, sqlTransport } from "../../src/blocks/memory/index.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";
import {
  chatIdOf,
  ConnectionAuthorizationRequiredError,
  credentialAuth,
  type EveSessionAuth,
  persistSessions,
  supabaseDocumentBackend,
  supabaseMemory,
} from "../../src/eve/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

/** Runs every call as the service role, as eve's hooks and providers do. */
function serviceTransport(s: BlockSession): BlockTransport {
  const inner = sqlTransport(s.sql);
  return {
    async call(schema, fn, args) {
      await s.service();
      return inner.call(schema, fn, args);
    },
  };
}

describe.skipIf(!live)("better-supabase/eve", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("stores each redelivered eve event once", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "ai-chat"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const service = serviceTransport(s);
      const hooks = persistSessions({
        chats: createAiChat({ transport: service, service }),
      });
      const auth: EveSessionAuth = {
        authenticator: "supabase",
        principalType: "user",
        principalId: owner.id,
        attributes: { tenantId: tenant },
      };
      const ctx = {
        session: { id: "sess_live", auth: { current: auth, initiator: auth } },
      };
      const turn = { turnId: "t1", sequence: 0 };
      const twice = async (deliver: () => Promise<void>) => {
        await deliver();
        await deliver();
      };
      await twice(() => hooks["session.started"]({ data: {} }, ctx));
      await twice(() => hooks["turn.started"]({ data: turn }, ctx));
      await twice(() =>
        hooks["message.received"](
          { data: { ...turn, sequence: 1, message: "Plan my week" } },
          ctx,
        ),
      );
      await twice(() =>
        hooks["message.completed"](
          {
            data: {
              ...turn,
              sequence: 2,
              stepIndex: 0,
              message: "Here is a plan",
              finishReason: "stop",
            },
          },
          ctx,
        ),
      );
      await twice(() =>
        hooks["turn.completed"]({ data: { ...turn, sequence: 3 } }, ctx),
      );

      await s.service();
      const chatId = await chatIdOf("sess_live");
      expect(
        await s.rows(
          "select organization_id, owner_id from better_supabase.ai_chats where id = $1",
          [chatId],
        ),
      ).toEqual([{ organization_id: tenant, owner_id: owner.id }]);
      expect(
        await s.rows(
          "select id, role, format, parent_id from better_supabase.ai_messages where chat_id = $1 order by role desc",
          [chatId],
        ),
      ).toEqual([
        { id: "t1:1", role: "user", format: "canonical", parent_id: null },
        {
          id: "t1:0:2",
          role: "assistant",
          format: "eve",
          parent_id: "t1:1",
        },
      ]);
      expect(
        await s.rows(
          "select status from better_supabase.ai_runs where chat_id = $1",
          [chatId],
        ),
      ).toEqual([{ status: "done" }]);
    } finally {
      await s.close();
    }
  });

  it("recalls once per operation and versions file memory", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "memory"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const memory = createMemory({
        transport: serviceTransport(s),
        embedder: wordEmbedder(),
      });
      const provider = supabaseMemory({ memory, tools: false });
      const auth: EveSessionAuth = {
        authenticator: "supabase",
        principalType: "user",
        principalId: owner.id,
        attributes: { tenantId: tenant },
      };
      const ctx = (operationId: string) => ({
        session: { id: "sess_mem", auth: { current: auth } },
        memory: { scope: { key: "agent:main" } },
        operationId,
        turn: {
          id: "t1",
          input: [{ role: "user", content: "what tea do I like?" }],
        },
      });
      const first = await provider.recall["turn.started"](ctx("op1"));
      const replay = await provider.recall["turn.started"](ctx("op1"));
      expect(replay).toEqual(first);
      await s.service();
      expect(
        await s.rows(
          "select path from better_supabase.memory_documents where scope_key = 'eve-ops'",
        ),
      ).toEqual([{ path: "agent:main/recall/op1" }]);

      const backend = supabaseDocumentBackend({ memory });
      const written = await backend.write({
        key: "agent:main/notes.md",
        content: "likes green tea",
        expectedVersion: null,
      });
      await expect(
        backend.write({
          key: "agent:main/notes.md",
          content: "stale",
          expectedVersion: null,
        }),
      ).rejects.toMatchObject({ name: "MemoryDocumentConflictError" });
      expect(await backend.read({ key: "agent:main/notes.md" })).toEqual(
        written,
      );
    } finally {
      await s.close();
    }
  });

  it("reads connection tokens from Vault for the app and the user", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["credentials"]);
      await s.service();
      const vault = vaultCredentials({ transport: sqlTransport(s.sql) });
      const app = { provider: "vault", secret: `eve-${crypto.randomUUID()}` };
      await vault.set(app, "lin_app", { subject: { type: "app" } }).orThrow();
      const auth = credentialAuth({ provider: vault, ref: app, owner: "app" });
      const connection = { url: "https://mcp.linear.app/mcp" };
      expect(
        await auth.getToken({ principal: { type: "app" }, connection }),
      ).toEqual({ token: "lin_app" });

      const userRef = {
        provider: "vault",
        secret: `eve-user-${crypto.randomUUID()}`,
        scope: "user",
      };
      const user = { type: "user", id: crypto.randomUUID() } as const;
      const perUser = credentialAuth({
        provider: vault,
        ref: userRef,
        owner: "user",
        connection: "linear",
      });
      expect(perUser.credentialOwner).toBe("user");
      await expect(
        perUser.getToken({ principal: user, connection }),
      ).rejects.toBeInstanceOf(ConnectionAuthorizationRequiredError);
      await vault
        .set(userRef, "lin_user", { subject: { type: "user", id: user.id } })
        .orThrow();
      expect(await perUser.getToken({ principal: user, connection })).toEqual({
        token: "lin_user",
      });
    } finally {
      await s.close();
    }
  });
});
