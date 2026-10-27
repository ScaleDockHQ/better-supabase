import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/blocks/ai-chat/index.ts";
import type { DbTransportSource } from "../../src/core/block-transport.ts";
import type { RequestContext } from "../../src/core/plugin.ts";
import type {
  EveApprovalResponseContext,
  EveSessionAuth,
  EveTargetHandle,
} from "../../src/eve/index.ts";

import { contextClaims } from "../../src/auth/delegation.ts";
import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createMemory, sqlTransport } from "../../src/blocks/memory/index.ts";
import { createQueue } from "../../src/blocks/queue/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";
import {
  approvalPolicy,
  chatIdOf,
  ConnectionAuthorizationRequiredError,
  credentialAuth,
  eveAgentJob,
  persistSessions,
  queueSchedules,
  scheduleAgent,
  supabaseDocumentBackend,
  supabaseMemory,
  supabaseTool,
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

/**
 * `server.forContext` over the session: the context's claims, as `forContext`
 * builds them, applied to the `authenticated` role so RLS decides.
 */
function contextServer(s: BlockSession) {
  // SAFETY: the tests pass their own block clients, so nothing reads the executor.
  const db = { $executor: { name: "block-session" } } as DbTransportSource;

  return {
    forContext: (
      context: RequestContext,
      options: { readonly permissions?: readonly string[] } = {},
    ) =>
      AsyncResult.from(async () => {
        const built = contextClaims(
          context,
          options.permissions === undefined
            ? {}
            : { permissions: options.permissions },
        );

        if (!built.ok) {
          return err(dbError("forbidden", built.message));
        }

        const { sub, ...claims } = built.claims;
        await s.asRole({ id: sub, email: "eve@example.test" }, claims);

        return ok(db);
      }),
  };
}

const member = (id: string, tenant: string): EveSessionAuth => ({
  authenticator: "supabase",
  principalType: "user",
  principalId: id,
  attributes: { tenantId: tenant },
});

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
        { id: "t1:0:2", role: "assistant", format: "eve", parent_id: "t1:1" },
      ]);
      expect(
        await s.rows(
          "select status from better_supabase.ai_runs where chat_id = $1",
          [chatId],
        ),
      ).toEqual([{ status: "completed" }]);
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

      expect(perUser).toMatchObject({ credentialOwner: "user" });
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

  it("runs a tool as the user with the agent claim, under RLS", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const outsider = await s.user("outsider");
      const elsewhere = await s.organization(outsider);
      await s.service();
      await s.client.query(`
        create schema eve_it;
        create table eve_it.tasks (
          id serial primary key,
          organization_id uuid not null,
          title text not null,
          created_by uuid not null default auth.uid(),
          agent text default (auth.jwt() -> 'act' ->> 'sub')
        );
        alter table eve_it.tasks enable row level security;
        create policy tasks_insert on eve_it.tasks for insert to authenticated
          with check (
            organization_id in (select better_supabase.tenant_ids_with('members.read'))
            and auth.jwt() -> 'act' ->> 'kind' = 'agent'
          );
        create policy tasks_read on eve_it.tasks for select to authenticated using (true);
        grant usage on schema eve_it to authenticated;
        grant select, insert on eve_it.tasks to authenticated;
        grant usage on sequence eve_it.tasks_id_seq to authenticated;
      `);

      const tool = (scopes?: readonly string[]) =>
        supabaseTool({
          server: contextServer(s),
          agent: "planner",
          ...(scopes === undefined ? {} : { scopes }),
          description: "Creates a task",
          inputSchema: v.object({ title: v.string() }),
          execute: async ({ title }, { context }) => {
            await s.client.query("savepoint tool");

            try {
              const { rows } = await s.client.query<{ id: number }>(
                "insert into eve_it.tasks (organization_id, title) values ($1, $2) returning id",
                [context.tenant, title],
              );

              return rows[0]?.id;
            } catch (error) {
              await s.client.query("rollback to savepoint tool");
              throw error;
            }
          },
        });

      const scoped = tool(["members.read"]);

      const call = (auth: EveSessionAuth) => ({
        session: { id: "sess_tool", auth: { current: auth, initiator: auth } },
        callId: "call_tool",
        toolName: "create_task",
      });

      await expect(
        tool().execute({ title: "Unscoped" }, call(member(owner.id, tenant))),
      ).rejects.toThrow(/row-level security/);
      await expect(
        scoped.execute({ title: "Ship it" }, call(member(owner.id, tenant))),
      ).resolves.toEqual(expect.any(Number));
      await s.service();
      expect(
        await s.rows("select title, created_by, agent from eve_it.tasks"),
      ).toEqual([{ title: "Ship it", created_by: owner.id, agent: "planner" }]);

      await expect(
        scoped.execute(
          { title: "Not yours" },
          call(member(owner.id, elsewhere)),
        ),
      ).rejects.toThrow(/row-level security/);
    } finally {
      await s.close();
    }
  });

  it("settles a two-step approval only after the second approver", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        ["organizations", "outbox", "notifications", "approvals"],
        {
          modules: {
            approvals: {
              options: {
                policies: {
                  eve_tool_call: {
                    create_task: {
                      steps: [
                        { approvers: { role: "owner" } },
                        { approvers: { role: "admin" } },
                      ],
                    },
                  },
                },
              },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const requester = await s.user("requester");
      const admin = await s.user("admin");
      const tenant = await s.organization(owner, { member: requester, admin });

      const policy = approvalPolicy({
        server: contextServer(s),
        agent: "planner",
        approvals: (_transport, org) =>
          createApprovals({ transport: sqlTransport(s.sql), tenant: org }),
      });

      const auth = member(requester.id, tenant);

      const request = () =>
        policy.request({
          session: {
            id: "sess_appr",
            auth: { current: auth, initiator: auth },
          },
          callId: "call_appr",
          toolName: "create_task",
          toolInput: { title: "Ship it" },
        });

      const respond = (responder: string): EveApprovalResponseContext => ({
        request: {
          callId: "call_appr",
          requestId: "input_1",
          principal: auth,
          toolName: "create_task",
        },
        response: { decision: "approve", principal: member(responder, tenant) },
        session: { id: "sess_appr" },
      });

      await expect(request()).resolves.toBe("user-approval");
      await expect(request()).resolves.toBe("user-approval");
      await expect(policy.response?.(respond(owner.id))).resolves.toMatchObject(
        { status: "rejected" },
      );
      await expect(request()).resolves.toBe("user-approval");
      await expect(policy.response?.(respond(admin.id))).resolves.toEqual({
        status: "allowed",
      });
      await expect(request()).resolves.toMatchObject({ type: "approved" });

      await s.service();
      expect(
        await s.rows(
          "select status, requested_by from better_supabase.approval_requests where subject_id = 'call_appr'",
        ),
      ).toEqual([{ status: "approved", requested_by: requester.id }]);
    } finally {
      await s.close();
    }
  });

  it("dispatches a tenant schedule once, as the user who set it", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "queue"], {
        modules: {
          queue: { options: { backend: "table", scheduler: "drain" } },
        },
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      await s.service();

      const queue = createQueue({ sql: s.sql, queues: { eve: eveAgentJob } });
      const name = `eve-digest-${crypto.randomUUID().slice(0, 8)}`;

      await scheduleAgent(
        queue,
        name,
        "0 9 * * *",
        { prompt: "Send the digest", channel: "slack", target: { id: "C1" } },
        {
          tenant,
          timeZone: "Europe/Amsterdam",
          context: { actor: { id: owner.id, kind: "user" }, tenant },
        },
      ).orThrow();
      await s.client.query(
        `update better_supabase.job_schedules
         set next_run = date_trunc('milliseconds', now()) - interval '1 minute'
         where job_name = $1`,
        [name],
      );

      const sent: { message: string; auth: EveSessionAuth | null }[] = [];

      const run = async () => {
        const tasks: Promise<unknown>[] = [];

        queueSchedules({ queue, channels: { slack: { name: "slack" } } })({
          to: (): EveTargetHandle => ({
            send: (message, { auth }) => {
              sent.push({ message, auth });

              return Promise.resolve({});
            },
          }),
          appAuth: member("app", tenant),
          waitUntil: (task) => {
            tasks.push(task);
          },
        });

        await Promise.all(tasks);
      };

      await run();
      await run();

      expect(sent).toEqual([
        {
          message: "Send the digest",
          auth: { ...member(owner.id, tenant), subject: owner.id },
        },
      ]);
    } finally {
      await s.close();
    }
  });
});
