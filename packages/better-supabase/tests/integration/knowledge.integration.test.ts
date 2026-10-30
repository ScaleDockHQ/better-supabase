import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Embedder } from "../../src/blocks/knowledge/index.ts";

import { driveSubject } from "../../src/blocks/drive/index.ts";
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

  it("shows a drive node's knowledge only to members who can read the node", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        [
          "organizations",
          "outbox",
          "teams",
          "share-links",
          "versions",
          "trash",
          "drive",
          "subjects",
          "knowledge",
        ],
        { subjects: { drive_node: driveSubject() } },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      const knowledge = createKnowledge({
        transport: sqlTransport(s.sql),
        embedder: wordEmbedder(),
      });

      await s.asRole(owner);

      const folder = await s.value<{ id: string }>(
        "better_supabase.drive_create_folder($1, null, 'Contracts')",
        [tenant],
      );

      const subject = { type: "drive_node", id: folder.id };

      const doc = await knowledge.ingest
        .text(tenant, {
          title: "Lease",
          text: "The lease renews every March.",
          scope: "subject",
          subject,
        })
        .orThrow();

      expect(doc).toMatchObject({ scope: "subject", subject });

      const missing = await knowledge.documents.create(tenant, {
        title: "x",
        scope: "subject",
      });

      expect(missing.ok ? undefined : missing.error.hint).toBe(
        "KNOWLEDGE_DOCUMENT_INVALID",
      );

      const search = () => knowledge.search(tenant, "lease").orThrow();

      expect((await search()).map((hit) => hit.documentId)).toEqual([doc.id]);

      await s.asRole(member);
      expect(await search()).toEqual([]);
      expect(
        await knowledge.documents.list(tenant, { subject }).orThrow(),
      ).toEqual([]);

      const hidden = await knowledge.documents.get(doc.id);

      expect(hidden.ok ? undefined : hidden.error.hint).toBe(
        "KNOWLEDGE_NOT_FOUND",
      );

      const foreign = await knowledge.documents.create(tenant, {
        title: "x",
        scope: "subject",
        subject,
      });

      expect(foreign.ok ? undefined : foreign.error.hint).toBe(
        "KNOWLEDGE_DOCUMENT_SUBJECT_NOT_FOUND",
      );

      await s.asRole(owner);
      await s.value("better_supabase.drive_share($1, 'user', $2, 'viewer')", [
        folder.id,
        member.id,
      ]);
      await s.asRole(member);
      expect((await search()).map((hit) => hit.documentId)).toEqual([doc.id]);
    } finally {
      await s.close();
    }
  });

  it("keeps a chunk rewritten during its embedding waiting", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "knowledge"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      let rewrite = true;
      const inner = wordEmbedder();

      const racing: Embedder = {
        model: inner.model,
        embed: async (values, options) => {
          if (rewrite) {
            rewrite = false;
            await s.client.query(
              "update better_supabase.knowledge_chunks set content = 'Koalas sleep' where content = 'Penguins swim'",
            );
          }

          return inner.embed(values, options);
        },
      };

      const knowledge = createKnowledge({
        transport: sqlTransport(s.sql),
        embedder: racing,
      });

      await s.asRole(owner);

      const doc = await knowledge.ingest
        .text(tenant, { title: "Race", text: "Penguins swim" })
        .orThrow();

      await s.service();
      expect(await knowledge.process(doc.id).orThrow()).toBe(0);

      const [row] = await s.rows<{ fresh: boolean }>(
        "select embedding_hash = md5(content) as fresh from better_supabase.knowledge_chunks where document_id = $1",
        [doc.id],
      );

      expect(row?.fresh).toBe(true);
      expect(inner.calls).toBe(2);
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

  it("grants a restricted collection to a team by its typed id", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "teams", "knowledge"]);
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const peer = await s.user("peer");

      const tenant = await s.organization(owner, {
        member: rep,
        member2: peer,
      });

      await s.as(owner);

      const team = await s.value<string>(
        "(better_supabase.create_team($1, 'Sales', null) ->> 'id')",
        [tenant],
      );

      await s.value("better_supabase.add_team_member($1, $2)", [team, rep.id]);

      const collection = await s.value<string>(
        "(better_supabase.create_knowledge_collection(tenant => $1, name => 'Playbooks', visibility => 'restricted') ->> 'id')",
        [tenant],
      );

      expect(
        await s.value<boolean>(
          "better_supabase.set_knowledge_collection_grant(collection_id => $1, team_id => $2::uuid)",
          [collection, team],
        ),
      ).toBe(true);
      expect(
        await s.value<string>(
          "(select format_type(atttypid, atttypmod) from pg_attribute where attrelid = 'better_supabase.knowledge_collection_grants'::regclass and attname = 'team_id')",
        ),
      ).toBe("uuid");
      expect(
        await s.value<string>(
          "(select organization_id::text from better_supabase.knowledge_collection_grants where collection_id = $1)",
          [collection],
        ),
      ).toBe(tenant);

      await s.as(rep);
      expect(
        await s.value<boolean>(
          "better_supabase.knowledge_collection_readable($1)",
          [collection],
        ),
      ).toBe(true);

      await s.as(peer);
      expect(
        await s.value<boolean>(
          "better_supabase.knowledge_collection_readable($1)",
          [collection],
        ),
      ).toBe(false);
    } finally {
      await s.close();
    }
  });
});
