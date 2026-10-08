import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  CredentialProvider,
  CredentialRef,
} from "../../src/credentials/provider.ts";

import { createAgents, sqlTransport } from "../../src/blocks/agents/index.ts";
import { createAiTasks } from "../../src/blocks/ai-tasks/index.ts";
import { createConnectors } from "../../src/blocks/connectors/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("agents, connectors and ai-tasks modules", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps private agents private and runs the store", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "agents"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const other = await s.user("other");
      const tenant = await s.organization(owner, { member, member2: other });
      const agents = createAgents({ transport: sqlTransport(s.sql) });

      await s.asRole(member);
      const created = await agents
        .create(tenant, {
          slug: "writer",
          name: "Writer",
          instructions: "Be brief",
          tools: ["search"],
          knowledgeScopes: [{ scope: "agent" }],
          starters: ["Draft a post"],
        })
        .orThrow();
      expect(created).toMatchObject({
        ownerId: member.id,
        visibility: "private",
        tools: ["search"],
      });
      const duplicate = await agents.create(tenant, {
        slug: "writer",
        name: "Again",
      });
      expect(duplicate.ok).toBe(false);
      await agents
        .setSkills(created.id, [
          { provider: "vercel", reference: { slug: "pdf" } },
        ])
        .orThrow();
      expect((await agents.get(created.id).orThrow()).skills).toHaveLength(1);

      await s.asRole(other);
      const hidden = await agents.get(created.id);
      expect(hidden.ok ? undefined : hidden.error.hint).toBe("AGENT_NOT_FOUND");
      const stolen = await agents.update(tenant, created.id, { name: "Mine" });
      expect(stolen.ok).toBe(false);

      await s.asRole(owner);
      await agents.publish(created.id, "organization").orThrow();

      await s.asRole(other);
      const store = await agents.list(tenant, { filter: "store" }).orThrow();
      expect(store.map((agent) => agent.id)).toEqual([created.id]);
      expect(await agents.install(tenant, created.id).orThrow()).toBe(true);
      const rated = await agents.rate(created.id, 4, "useful").orThrow();
      expect(rated).toMatchObject({ ratingCount: 1, rating: 4 });
      const installed = await agents
        .list(tenant, { filter: "installed" })
        .orThrow();
      expect(installed[0]).toMatchObject({ installed: true, installCount: 1 });
      expect((await agents.bySlug(tenant, "writer").orThrow()).myRating).toBe(
        4,
      );
      const badRating = await agents.rate(created.id, 9);
      expect(badRating.ok).toBe(false);
      expect(await agents.remove(created.id).orThrow()).toBe(false);

      await s.asRole(member);
      expect(await agents.remove(created.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("records grants, revokes their credentials and gates tool changes", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "connectors"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const revoked: CredentialRef[] = [];
      const credentials: CredentialProvider = {
        apiVersion: 1,
        name: "fake",
        capabilities: () => ({
          userSubjects: true,
          authorization: false,
          revoke: true,
          inbound: false,
        }),
        getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
        revoke: (ref) => {
          revoked.push(ref);
          return AsyncResult.ok(true);
        },
      };
      const transport = sqlTransport(s.sql);
      const connectors = createConnectors({ transport, credentials });

      await s.asRole(member);
      const denied = await connectors.servers.create(tenant, {
        name: "GitHub",
        url: "https://mcp.example.com/mcp",
      });
      expect(denied.ok).toBe(false);

      await s.asRole(owner);
      const insecure = await connectors.servers.create(tenant, {
        name: "Plain",
        url: "http://mcp.example.com/mcp",
      });
      expect(insecure.ok).toBe(false);
      const server = await connectors.servers
        .create(tenant, {
          name: "GitHub",
          url: "https://mcp.example.com/mcp",
          authType: "oauth",
          scopes: ["repo"],
        })
        .orThrow();

      await s.service();
      const ref = {
        provider: "vault",
        secret: `mcp:${server.id}`,
        scope: "user",
      };
      await connectors.grants
        .record(server.id, member.id, ref, { scopes: ["repo"] })
        .orThrow();
      // A reconnect with the same ref keeps the credential.
      await connectors.grants.record(server.id, member.id, ref).orThrow();
      expect(revoked).toEqual([]);
      const other = { provider: "vercel-connect", connector: "github" };
      await connectors.grants.record(server.id, member.id, other).orThrow();
      expect(revoked).toEqual([ref]);
      const viaService = await connectors.servers
        .get(server.id, { ownerId: member.id })
        .orThrow();
      expect(viaService.grant?.credentialRef).toEqual(other);

      await s.asRole(member);
      const [listed] = await connectors.servers.list(tenant).orThrow();
      expect(listed?.grant?.credentialRef).toEqual(other);

      expect(
        await connectors.fingerprints
          .check(server.id, "sha256:a", { a: "1" })
          .orThrow(),
      ).toBe("approved");
      expect(
        await connectors.fingerprints.check(server.id, "sha256:b").orThrow(),
      ).toBe("pending");
      const notAdmin = await connectors.fingerprints.approve(
        server.id,
        "sha256:b",
      );
      expect(notAdmin.ok).toBe(false);

      expect(
        await connectors.sessions
          .save(server.id, {
            chatKey: "c1",
            sessionId: "sess",
            initializeResult: { protocolVersion: "2025-11-25" },
          })
          .orThrow(),
      ).toBe(true);
      expect(
        await connectors.sessions.get(server.id, "c1").orThrow(),
      ).toMatchObject({
        sessionId: "sess",
      });

      await s.asRole(owner);
      expect(
        await connectors.fingerprints.approve(server.id, "sha256:b").orThrow(),
      ).toBe(true);
      expect(
        await connectors.sessions.get(server.id, "c1").orThrow(),
      ).toBeUndefined();

      await s.asRole(member);
      expect(
        await connectors.fingerprints.check(server.id, "sha256:b").orThrow(),
      ).toBe("approved");
      expect(
        await connectors.grants.revoke(viaService.grant?.id ?? "").orThrow(),
      ).toBe(true);
      expect(revoked).toEqual([ref, other]);
      expect(
        await connectors.sessions.get(server.id, "c1").orThrow(),
      ).toBeUndefined();

      await s.service();
      await connectors.grants.record(server.id, member.id, ref).orThrow();
      await s.asRole(owner);
      expect(await connectors.servers.remove(server.id).orThrow()).toBe(1);
      expect(revoked).toEqual([ref, other, ref]);
    } finally {
      await s.close();
    }
  });

  it("claims due tasks, runs them and schedules the next run", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "agents", "ai-tasks"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const past = Temporal.Instant.from("2020-01-01T08:00:00Z");
      const seen: string[] = [];
      let clock = past;
      const tasks = createAiTasks({
        transport,
        now: () => clock,
        run: (task) => {
          seen.push(task.prompt);
          return Promise.resolve({});
        },
      });

      await s.asRole(member);
      const task = await tasks
        .create(tenant, {
          title: "Digest",
          prompt: "Summarize my day",
          cron: "0 9 * * *",
        })
        .orThrow();
      expect(task.nextRunAt?.toString()).toBe("2020-01-01T09:00:00Z");
      const bad = await tasks.create(tenant, {
        title: "x",
        prompt: "y",
        cron: "0 9 * * *",
        agentId: crypto.randomUUID(),
      });
      expect(bad.ok).toBe(false);

      clock = Temporal.Now.instant();
      await s.service();
      expect(await tasks.drain().orThrow()).toBe(1);
      expect(seen).toEqual(["Summarize my day"]);
      const second = await tasks.tick().orThrow();
      expect(second).toEqual([]);

      await s.asRole(member);
      const [listed] = await tasks.list(tenant).orThrow();
      expect(listed?.lastRun?.status).toBe("succeeded");
      expect(Temporal.Instant.compare(listed?.nextRunAt ?? past, clock)).toBe(
        1,
      );
      const runs = await tasks.runs(task.id).orThrow();
      expect(runs.map((run) => run.status)).toEqual(["succeeded"]);
      const paused = await tasks.pause(tenant, task.id).orThrow();
      expect(paused).toMatchObject({ enabled: false, nextRunAt: undefined });
      expect(await tasks.remove(task.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });
});
