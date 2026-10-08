import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Embedder } from "../../src/blocks/knowledge/index.ts";

import {
  createKnowledge,
  sqlTransport,
} from "../../src/blocks/knowledge/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

describe.skipIf(!live)("knowledge module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("ingests, embeds and finds chunks the caller may read", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-chat", "ai-files", "knowledge"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });
      const embedder = wordEmbedder();
      const knowledge = createKnowledge({
        transport: sqlTransport(s.sql),
        embedder,
        chunking: { size: 60, overlap: 0 },
      });

      await s.asRole(member);
      const text =
        "Penguins live in the southern hemisphere.\n\nKoalas sleep most of the day in eucalyptus trees.";
      const doc = await knowledge.ingest
        .text(tenant, { title: "Animals", text, metadata: { topic: "zoo" } })
        .orThrow();
      expect(doc).toMatchObject({
        status: "pending",
        chunkCount: 2,
        scope: "user",
        ownerId: member.id,
        embeddingModel: "words-v1",
      });

      const textOnly = await knowledge
        .search(tenant, { text: "koalas" })
        .orThrow();
      expect(textOnly.map((hit) => hit.index)).toEqual([1]);

      await s.service();
      expect(await knowledge.process(doc.id).orThrow()).toBe(0);
      await s.asRole(member);
      expect((await knowledge.documents.get(doc.id).orThrow()).status).toBe(
        "ready",
      );

      const hits = await knowledge
        .search(tenant, "where do penguins live", { k: 1 })
        .orThrow();
      expect(hits[0]).toMatchObject({
        documentId: doc.id,
        index: 0,
        title: "Animals",
      });
      expect(hits[0]!.content).toContain("Penguins");
      expect(
        await knowledge
          .search(tenant, "penguins", { filter: { topic: "x" } })
          .orThrow(),
      ).toEqual([]);

      const calls = embedder.calls;
      const edited = await knowledge.documents
        .write(doc.id, [
          { content: "Penguins live in the southern hemisphere." },
          { content: "Koalas eat eucalyptus leaves." },
        ])
        .orThrow();
      expect(edited.status).toBe("pending");
      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::integer from better_supabase.knowledge_chunks where document_id = $1 and embedding is null)",
          [doc.id],
        ),
      ).toBe(1);
      await knowledge.process(doc.id).orThrow();
      expect(embedder.calls).toBe(calls + 1);

      await s.asRole(outsider);
      expect(await knowledge.search(tenant, "penguins").orThrow()).toEqual([]);
      const foreign = await knowledge.documents.get(doc.id);
      expect(foreign.ok ? undefined : foreign.error.hint).toBe(
        "KNOWLEDGE_NOT_FOUND",
      );
      const forbidden = await knowledge.documents.create(tenant, {
        title: "x",
      });
      expect(forbidden.ok ? undefined : forbidden.error.hint).toBe(
        "KNOWLEDGE_FORBIDDEN",
      );

      await s.asRole(owner);
      const shared = await knowledge.ingest
        .text(tenant, {
          title: "Handbook",
          text: "Expenses are reimbursed monthly.",
          scope: "organization",
        })
        .orThrow();
      await s.asRole(member);
      const visible = await knowledge
        .search(tenant, "expenses", { scopes: [{ scope: "organization" }] })
        .orThrow();
      expect(visible.map((hit) => hit.documentId)).toEqual([shared.id]);
      expect(await knowledge.documents.remove(shared.id).orThrow()).toBe(false);
      const badScope = await knowledge.documents.create(tenant, {
        title: "x",
        scope: "agent",
      });
      expect(badScope.ok ? undefined : badScope.error.hint).toBe(
        "KNOWLEDGE_FORBIDDEN",
      );
      await s.asRole(owner);
      const noAgent = await knowledge.documents.create(tenant, {
        title: "x",
        scope: "agent",
      });
      expect(noAgent.ok ? undefined : noAgent.error.hint).toBe(
        "KNOWLEDGE_SCOPE",
      );

      await s.service();
      expect(
        await knowledge.reembed({ organizationId: tenant }).orThrow(),
      ).toBe(2);
      expect(await knowledge.drain().orThrow()).toBe(2);
      expect(
        await knowledge
          .reembed({ organizationId: tenant, model: "words-v1" })
          .orThrow(),
      ).toBe(0);

      await s.asRole(member);
      const listed = await knowledge.documents.list(tenant).orThrow();
      expect(listed.map((d) => d.id).toSorted()).toEqual(
        [doc.id, shared.id].toSorted(),
      );
      expect(await knowledge.documents.remove(doc.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("marks a document failed when the embed job gives up", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "knowledge"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const failing: Embedder = {
        model: "broken",
        embed: () => Promise.reject(new Error("rate limited")),
      };
      const knowledge = createKnowledge({
        transport: sqlTransport(s.sql),
        embedder: failing,
      });
      await s.asRole(owner);
      const doc = await knowledge.ingest
        .text(tenant, { title: "Notes", text: "Some notes." })
        .orThrow();
      await s.service();
      const handler = knowledge.embedJob();
      const job = { attempts: 3, maxAttempts: 3 };
      await expect(
        Promise.resolve(
          handler(
            { document_id: doc.id },
            // SAFETY: the handler reads only attempts and maxAttempts.
            job as never,
            new AbortController().signal,
          ),
        ),
      ).rejects.toThrow("rate limited");
      expect(
        await s.value<string>(
          "(select status from better_supabase.knowledge_documents where id = $1)",
          [doc.id],
        ),
      ).toBe("failed");
    } finally {
      await s.close();
    }
  });
});
