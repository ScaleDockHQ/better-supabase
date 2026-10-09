import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAiCache } from "../../src/blocks/ai-cache/index.ts";
import {
  createAiProviders,
  sqlTransport,
} from "../../src/blocks/ai-providers/index.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("ai-cache and ai-providers modules", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("caches entries with a capped TTL and purges expired ones", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-cache"], {
        modules: { "ai-cache": { options: { maxTtl: 120 } } },
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      await s.service();
      const cache = createAiCache({ transport: sqlTransport(s.sql) });

      const saved = await cache
        .set(
          "k1",
          { text: "hi" },
          { ttl: 3600, organizationId: tenant, model: "openai/gpt-5" },
        )
        .orThrow();
      expect(
        saved.expiresAt.since(saved.createdAt).total("seconds"),
      ).toBeLessThanOrEqual(120);
      const hit = await cache.get<{ text: string }>("k1").orThrow();
      expect(hit).toMatchObject({ value: { text: "hi" }, hits: 1 });
      expect(await cache.get("missing").orThrow()).toBeUndefined();

      const tooBig = await cache.set("big", "x".repeat(2 * 1024 * 1024), {
        ttl: 60,
      });
      expect(tooBig.ok).toBe(false);
      const noFilter = await cache.clear({});
      expect(noFilter.ok).toBe(false);

      await cache.set("k2", 1, { ttl: 60 }).orThrow();
      await s.rows(
        "update better_supabase.ai_cache_entries set expires_at = now() - interval '1 second' where key = 'k2'",
      );
      expect(await cache.get("k2").orThrow()).toBeUndefined();
      expect(await cache.purge().orThrow()).toBe(1);
      expect(await cache.clear({ organizationId: tenant }).orThrow()).toBe(1);

      await s.asRole(owner);
      const denied = await cache.get("k1");
      expect(denied.ok).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("stores tenant keys as Vault refs, resolves them and revokes on delete", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "credentials", "ai-providers"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const credentials = vaultCredentials({ transport, cacheMs: 0 });
      const providers = createAiProviders({ transport, credentials });
      const ref = {
        provider: "vault",
        secret: `ai-${crypto.randomUUID()}`,
        tenant,
      };
      const backup = {
        provider: "vault",
        secret: `ai-${crypto.randomUUID()}`,
        tenant,
      };

      await s.service();
      await credentials.set(ref, "sk-ant-1").orThrow();
      await credentials.set(backup, "sk-ant-2").orThrow();

      await s.asRole(member);
      const forbidden = await providers.keys.save(tenant, {
        provider: "anthropic",
        credentialRef: ref,
      });
      expect(forbidden.ok).toBe(false);

      await s.asRole(owner);
      const badRef = await providers.keys.save(tenant, {
        provider: "anthropic",
        credentialRef: { name: "no-provider" } as never,
      });
      expect(badRef.ok).toBe(false);
      expect(
        await s.hint("better_supabase.save_ai_provider_key($1, $2, $3)", [
          tenant,
          "anthropic",
          { provider: "vault", secret: "theirs", tenant: crypto.randomUUID() },
        ]),
      ).toBe("CREDENTIAL_REF_FOREIGN");
      const saved = await providers.keys
        .save(tenant, {
          provider: "anthropic",
          credentialRef: ref,
          settings: { region: "eu" },
        })
        .orThrow();
      expect(saved).toMatchObject({ provider: "anthropic", name: "default" });
      expect(await providers.keys.list(tenant).orThrow()).toHaveLength(1);

      await s.asRole(member);
      expect(await providers.keys.list(tenant).orThrow()).toEqual([]);

      await s.service();
      const resolved = await providers.keys.resolve(tenant).orThrow();
      expect(resolved).toEqual([
        expect.objectContaining({
          provider: "anthropic",
          token: "sk-ant-1",
          settings: { region: "eu" },
        }),
      ]);

      await providers.keys
        .save(tenant, { provider: "anthropic", credentialRef: backup })
        .orThrow();
      const old = await credentials.getToken(ref, { subject: { type: "app" } });
      expect(old.ok ? "kept" : old.error.kind).toBe("not_found");

      expect(await providers.keys.removeAll(tenant).orThrow()).toBe(1);
      const gone = await credentials.getToken(backup, {
        subject: { type: "app" },
      });
      expect(gone.ok ? "kept" : gone.error.kind).toBe("not_found");
      expect(await providers.keys.resolve(tenant).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("tracks a batch through polling and pages its results", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-providers"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const other = await s.user("other");
      const tenant = await s.organization(owner, { member, member2: other });
      const providers = createAiProviders({ transport: sqlTransport(s.sql) });

      await s.asRole(member);
      const batch = await providers.batches
        .record(tenant, {
          provider: "openai",
          reference: { version: 2, id: "batch_1", provider: "openai" },
          itemCount: 2,
          userId: other.id,
        })
        .orThrow();
      expect(batch).toMatchObject({ userId: member.id, status: "pending" });

      await s.asRole(other);
      expect(await providers.batches.get(batch.id).orThrow()).toBeUndefined();

      await s.service();
      expect(await providers.batches.due().orThrow()).toEqual([]);
      await s.rows(
        "update better_supabase.ai_batches set next_poll_at = now() - interval '1 second' where id = $1",
        [batch.id],
      );
      const due = await providers.batches.due().orThrow();
      expect(due.map((row) => row.id)).toEqual([batch.id]);
      expect(due[0]?.polls).toBe(1);
      expect(await providers.batches.due().orThrow()).toEqual([]);

      await providers.batches
        .update(batch.id, {
          status: "completed",
          counts: { total: 2, completed: 2 },
        })
        .orThrow();
      expect(
        await providers.batches
          .saveItems(batch.id, [
            { requestId: "a", status: "succeeded", output: { text: "A" } },
            { requestId: "b", status: "failed", error: "bad" },
          ])
          .orThrow(),
      ).toBe(2);
      const done = await providers.batches
        .update(batch.id, { resultsSaved: true, nextPollAt: null })
        .orThrow();
      expect(done.completedAt).toBeDefined();

      await s.asRole(member);
      const first = await providers.batches
        .items(batch.id, { limit: 1 })
        .orThrow();
      expect(first.map((item) => item.requestId)).toEqual(["a"]);
      const rest = await providers.batches
        .items(batch.id, { after: "a" })
        .orThrow();
      expect(rest).toMatchObject([{ requestId: "b", error: "bad" }]);

      await s.asRole(owner);
      expect(await providers.batches.list(tenant).orThrow()).toHaveLength(1);
    } finally {
      await s.close();
    }
  });

  it("stops idle sandboxes and keeps used ones", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-providers"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const otherTenant = await s.organization(await s.user("rival"));
      const providers = createAiProviders({ transport: sqlTransport(s.sql) });
      const chatId = crypto.randomUUID();

      await s.service();
      const idle = await providers.sandboxes
        .register(tenant, {
          provider: "vercel",
          sandboxId: "sbx_idle",
          chatId,
          idleSeconds: 60,
        })
        .orThrow();
      const busy = await providers.sandboxes
        .register(tenant, { provider: "vercel", sandboxId: "sbx_busy" })
        .orThrow();
      const taken = await providers.sandboxes.register(otherTenant, {
        provider: "vercel",
        sandboxId: "sbx_idle",
      });
      expect(taken.ok ? undefined : taken.error.hint).toBe(
        "AI_SANDBOX_FORBIDDEN",
      );
      expect(
        (await providers.sandboxes.forChat(chatId, "vercel").orThrow())?.id,
      ).toBe(idle.id);

      await s.rows(
        "update better_supabase.ai_sandboxes set last_used_at = now() - interval '2 hours' where id = $1",
        [idle.id],
      );
      expect(await providers.sandboxes.touch(busy.id).orThrow()).toBe(true);

      const stopped: string[] = [];
      expect(
        await providers.sandboxes
          .stopIdle(async (sandbox) => {
            stopped.push(sandbox.sandboxId);
          })
          .orThrow(),
      ).toBe(1);
      expect(stopped).toEqual(["sbx_idle"]);

      await s.asRole(owner);
      const listed = await providers.sandboxes.list(tenant).orThrow();
      expect(
        Object.fromEntries(listed.map((row) => [row.sandboxId, row.status])),
      ).toEqual({ sbx_idle: "stopped", sbx_busy: "running" });
    } finally {
      await s.close();
    }
  });
});
