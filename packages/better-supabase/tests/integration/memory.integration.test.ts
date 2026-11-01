import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createMemory, sqlTransport } from "../../src/blocks/memory/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

describe.skipIf(!live)("memory module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs the memory tool commands on the caller's own files", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "memory"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      const memory = createMemory({
        transport: sqlTransport(s.sql),
        maxRender: 120,
      });

      await s.asRole(member);
      expect(
        await memory
          .run({
            organizationId: tenant,
            command: { command: "view", path: "/memories" },
          })
          .orThrow(),
      ).toBe("Here are the files in /memories:\n");
      expect(
        await memory
          .run({
            organizationId: tenant,
            command: {
              command: "create",
              path: "/memories/prefs.md",
              file_text: "likes tea\nworks remotely",
            },
          })
          .orThrow(),
      ).toBe("File created successfully at: /memories/prefs.md");
      await memory
        .run({
          organizationId: tenant,
          command: {
            command: "str_replace",
            path: "/memories/prefs.md",
            old_str: "tea",
            new_str: "green tea",
          },
        })
        .orThrow();
      await memory
        .run({
          organizationId: tenant,
          command: {
            command: "insert",
            path: "/memories/prefs.md",
            insert_line: 0,
            insert_text: "# Preferences",
          },
        })
        .orThrow();
      expect(
        await memory
          .run({
            organizationId: tenant,
            command: {
              command: "view",
              path: "/memories/prefs.md",
              view_range: [2, 2],
            },
          })
          .orThrow(),
      ).toBe(
        "Here's the content of /memories/prefs.md with line numbers:\n     2\tlikes green tea",
      );

      const ambiguous = await memory.core.strReplace({
        organizationId: tenant,
        path: "/memories/prefs.md",
        oldText: "e",
        newText: "E",
      });

      expect(ambiguous.ok ? undefined : ambiguous.error.hint).toBe(
        "MEMORY_AMBIGUOUS",
      );

      const missing = await memory.core.strReplace({
        organizationId: tenant,
        path: "/memories/prefs.md",
        oldText: "coffee",
        newText: "tea",
      });

      expect(missing.ok ? undefined : missing.error.hint).toBe(
        "MEMORY_NO_MATCH",
      );

      const stale = await memory.core.write({
        organizationId: tenant,
        path: "/memories/prefs.md",
        content: "x",
        ns: {},
        expectedVersion: 1,
      });

      expect(stale.ok ? undefined : stale.error.hint).toBe("MEMORY_CONFLICT");

      const escape = await memory.core.write({
        organizationId: tenant,
        path: "/memories/../etc",
        content: "x",
      });

      expect(escape.ok ? undefined : escape.error.hint).toBe("MEMORY_PATH");

      await memory
        .run({
          organizationId: tenant,
          command: {
            command: "rename",
            old_path: "/memories/prefs.md",
            new_path: "/memories/me/prefs.md",
          },
        })
        .orThrow();

      const listing = await memory.core
        .view({ organizationId: tenant })
        .orThrow();

      expect(listing).toMatchObject({
        type: "directory",
        entries: [{ path: "/memories/me/prefs.md" }],
      });

      const rendered = await memory
        .render({ organizationId: tenant })
        .orThrow();

      expect(rendered).toContain('<memory path="/memories/me/prefs.md">');
      await memory.core.write({
        organizationId: tenant,
        path: "/memories/long.md",
        content: "x".repeat(200),
      });
      expect(
        await memory.render({ organizationId: tenant }).orThrow(),
      ).toContain("the rest is cut");

      await s.asRole(owner);
      expect(
        await memory.core
          .view({ organizationId: tenant, path: "/memories/me" })
          .orThrow(),
      ).toBeUndefined();
      await memory.core
        .write({
          organizationId: tenant,
          path: "/memories/policy.md",
          content: "Answer in English.",
          ns: { scope: "organization" },
        })
        .orThrow();
      await s.asRole(member);
      expect(
        await memory.core
          .view({
            organizationId: tenant,
            path: "/memories/policy.md",
            ns: { scope: "organization" },
          })
          .orThrow(),
      ).toMatchObject({ type: "file", content: "Answer in English." });

      const denied = await memory.core.write({
        organizationId: tenant,
        path: "/memories/policy.md",
        content: "x",
        ns: { scope: "organization" },
      });

      expect(denied.ok ? undefined : denied.error.hint).toBe(
        "MEMORY_FORBIDDEN",
      );

      const noAgent = await memory.core.view({
        organizationId: tenant,
        path: "/memories",
        ns: { scope: "agent" },
      });

      expect(noAgent.ok ? undefined : noAgent.error.hint).toBe(
        "MEMORY_NAMESPACE",
      );

      expect(
        await memory
          .run({
            organizationId: tenant,
            command: { command: "delete", path: "/memories/me" },
          })
          .orThrow(),
      ).toBe("Successfully deleted /memories/me");
      expect(
        await memory
          .run({
            organizationId: tenant,
            command: { command: "view", path: "/memories/me" },
          })
          .orThrow(),
      ).toBe("/memories/me does not exist.");
    } finally {
      await s.close();
    }
  });

  it("saves, finds and dedupes archival facts and recalls messages", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-chat", "memory"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const embedder = wordEmbedder();
      const memory = createMemory({ transport: sqlTransport(s.sql), embedder });

      await s.asRole(owner);

      const fact = await memory.archival
        .upsert({
          organizationId: tenant,
          content: "The user has a dog named Rex.",
        })
        .orThrow();

      expect(fact).toMatchObject({
        kind: "archival",
        embeddingModel: "words-v1",
      });

      const hits = await memory.archival
        .search({ organizationId: tenant, query: "what is the dog called" })
        .orThrow();

      expect(hits[0]).toMatchObject({ id: fact.id });
      expect(hits[0]!.similarity).toBeGreaterThan(0);

      await s.service();
      const ns = { ownerId: owner.id };

      const saved = await memory
        .saveExtracted({
          organizationId: tenant,
          facts: [
            "The user has a dog named Rex.",
            "The user lives in Utrecht.",
            " ",
          ],
          ns,
        })
        .orThrow();

      expect(saved.map((record) => record.content)).toEqual([
        "The user lives in Utrecht.",
      ]);
      await s.client.query(
        "update better_supabase.memories set embedding = null where id = $1",
        [fact.id],
      );
      expect(await memory.embedPending().orThrow()).toBe(1);

      await s.client.query("set local hnsw.iterative_scan = 'strict_order'");
      await memory.archival
        .search({ organizationId: tenant, query: "dog", ns })
        .orThrow();
      expect(
        await s.value<string>("current_setting('hnsw.iterative_scan')"),
      ).toBe("strict_order");

      await s.client.query(
        "update better_supabase.memories set embedding = null where id = $1",
        [fact.id],
      );

      const editing = createMemory({
        transport: sqlTransport(s.sql),
        embedder: {
          model: embedder.model,
          embed: async (values, options) => {
            await s.client.query(
              "update better_supabase.memories set content = 'The user has a cat.' where id = $1",
              [fact.id],
            );

            return embedder.embed(values, options);
          },
        },
      });

      expect(await editing.embedPending().orThrow()).toBe(0);
      expect(
        await s.value<boolean>(
          "(select embedding is null from better_supabase.memories where id = $1)",
          [fact.id],
        ),
      ).toBe(true);
      expect(await memory.embedPending().orThrow()).toBe(1);

      await s.asRole(owner);

      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Pets" }],
      );

      const secret = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Secret", is_temporary: true }],
      );

      await s.service();

      const index = (chatId: string, messageId: string, text: string) =>
        memory.recall
          .index({
            organizationId: tenant,
            chatId,
            messageId,
            userId: owner.id,
            text,
          })
          .orThrow();

      expect(await index(chat.id, "m1", "my dog Rex loves the beach")).toBe(
        true,
      );
      expect(await index(secret.id, "m2", "my dog Rex is sick")).toBe(false);

      await s.asRole(owner);

      const recalled = await memory.recall
        .search({ organizationId: tenant, query: "dog beach" })
        .orThrow();

      expect(recalled).toMatchObject([{ chatId: chat.id, messageId: "m1" }]);
      expect(
        await memory.recall
          .search({
            organizationId: tenant,
            query: "dog",
            excludeChat: chat.id,
          })
          .orThrow(),
      ).toEqual([]);

      const listed = await memory.archival
        .list({ organizationId: tenant })
        .orThrow();

      expect(listed).toHaveLength(2);
      expect(
        await memory.archival.forget({ memoryId: fact.id }).orThrow(),
      ).toBe(true);
      expect(
        await memory.archival.list({ organizationId: tenant }).orThrow(),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });

  it("writes documents only at the version the caller read", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "memory"]);
      const owner = await s.user("owner");
      const memory = createMemory({ transport: sqlTransport(s.sql) });

      await s.asRole(owner);
      expect(
        (await memory.documents.read({ scopeKey: "scope", path: "/a.md" }))
          .error?.kind,
      ).toBeDefined();

      await s.service();
      expect(
        await memory.documents
          .read({ scopeKey: "scope", path: "/a.md" })
          .orThrow(),
      ).toBeUndefined();

      const first = await memory.documents
        .write({
          scopeKey: "scope",
          path: "/a.md",
          content: "one",
          options: { expectedVersion: null },
        })
        .orThrow();

      expect(first).toEqual({ content: "one", version: "1" });

      const again = await memory.documents.write({
        scopeKey: "scope",
        path: "/a.md",
        content: "two",
        options: { expectedVersion: null },
      });

      expect(again.error?.hint).toBe("MEMORY_DOCUMENT_CONFLICT");

      const second = await memory.documents
        .write({
          scopeKey: "scope",
          path: "/a.md",
          content: "two",
          options: { expectedVersion: "1" },
        })
        .orThrow();

      expect(second.version).toBe("2");

      const stale = await memory.documents.write({
        scopeKey: "scope",
        path: "/a.md",
        content: "three",
        options: { expectedVersion: "1" },
      });

      expect(stale.error?.hint).toBe("MEMORY_DOCUMENT_CONFLICT");
      expect(
        await memory.documents
          .read({ scopeKey: "other", path: "/a.md" })
          .orThrow(),
      ).toBeUndefined();

      await memory.documents
        .write({
          scopeKey: "scope",
          path: "/tmp.md",
          content: "gone",
          options: { expectedVersion: null, expiresIn: 1 },
        })
        .orThrow();
      await s.client.query(
        "update better_supabase.memory_documents set expires_at = now() - interval '1 second' where path = '/tmp.md'",
      );
      expect(
        await memory.documents
          .read({ scopeKey: "scope", path: "/tmp.md" })
          .orThrow(),
      ).toBeUndefined();
      expect(
        await memory.documents
          .write({
            scopeKey: "scope",
            path: "/tmp.md",
            content: "back",
            options: { expectedVersion: null },
          })
          .orThrow(),
      ).toEqual({ content: "back", version: "1" });
      await s.client.query(
        "update better_supabase.memory_documents set expires_at = now() - interval '1 second' where path = '/tmp.md'",
      );
      expect(await memory.documents.purge().orThrow()).toBe(1);
    } finally {
      await s.close();
    }
  });
});
