import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAgents } from "../../src/blocks/agents/index.ts";
import { createKnowledge } from "../../src/blocks/knowledge/index.ts";
import { createKnowledge } from "../../src/blocks/knowledge/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

/**
 * One transaction gives every row the same now(), and a sort needs distinct
 * values.
 */
async function spreadTimes(
  s: BlockSession,
  table: string,
  columns: readonly string[],
): Promise<void> {
  await s.client.query("reset role");
  await s.client.query(
    `update better_supabase.${table} a set ${columns.map((column) => `${column} = now() + (r.n || ' minutes')::interval`).join(", ")} from (select id, row_number() over (order by random()) as n from better_supabase.${table}) r where r.id = a.id`,
  );
}

describe.skipIf(!live)("the F11 block lists follow the list contract", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages agents in the mine mode", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "agents"]);
      const owner = await s.user("agents-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const agents = createAgents({ transport: sqlTransport(s.sql) });

      for (const name of [
        "Alpha one",
        "Alpha twos",
        "Beta three",
        "Beta fours",
        "Gamma fiv",
      ]) {
        const created = await agents
          .create({
            organizationId: org,
            agent: { slug: name.toLowerCase().replace(" ", "-"), name },
          })
          .orThrow();

        if (name.startsWith("Beta") || name.startsWith("Gamma")) {
          await agents
            .publish({ agentId: created.id, visibility: "organization" })
            .orThrow();
        }
      }

      // One transaction gives every row the same now(), and a sort needs distinct values.
      await s.client.query("reset role");
      await s.client.query(
        `update better_supabase.agents a set created_at = now() + (r.n || ' minutes')::interval, updated_at = now() + (r.n || ' minutes')::interval from (select id, row_number() over (order by random()) as n from better_supabase.agents) r where r.id = a.id`,
      );
      await s.asRole(owner);

      const mine = (filters?: Readonly<Record<string, readonly string[]>>) => ({
        mode: ["mine"],
        ...filters,
      });

      // The store holds what is published; installing adds to the installed mode.
      const storeIds = (
        await agents.page({ organizationId: org, limit: 50 }).orThrow()
      ).items.map((agent) => agent.name);

      expect(storeIds.toSorted()).toEqual(
        ["Beta three", "Beta fours", "Gamma fiv"].toSorted(),
      );

      const [first] = (
        await agents.page({ organizationId: org, limit: 1 }).orThrow()
      ).items;

      await agents
        .install({ organizationId: org, agentId: first?.id ?? "" })
        .orThrow();

      const installed = await agents
        .page({ organizationId: org, filters: { mode: ["installed"] } })
        .orThrow();

      expect(installed.items.map((agent) => agent.id)).toEqual([first?.id]);

      const badMode = await agents.page({
        organizationId: org,
        filters: { mode: ["everything"] },
      });

      expect(badMode.ok).toBe(false);

      await testBlockList({
        name: "agents",
        target: {
          page: (options) =>
            agents.page({
              ...options,
              organizationId: org,
              filters: mine(options?.filters),
            }),
          count: (options) =>
            agents.count({
              ...options,
              organizationId: org,
              filters: mine(options?.filters),
            }),
          facets: (options) =>
            agents.facets({
              ...options,
              organizationId: org,
              filters: mine(options?.filters),
            }),
          get: (id) => agents.get(id),
        },
        rows: 5,
        sorts: ["name", "updatedAt", "createdAt"],
        facets: { visibility: { private: 2, organization: 3 } },
        arrayFilter: {
          column: "visibility",
          values: ["private", "organization"],
        },
        search: "Alpha",
      });
    } finally {
      await s.close();
    }
  });

  it("pages knowledge documents and collections", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-chat", "ai-files", "knowledge"]);
      const owner = await s.user("knowledge-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const knowledge = createKnowledge({ transport: sqlTransport(s.sql) });

      for (const [index, title] of [
        "Alpha doc",
        "Alpha note",
        "Beta doc",
        "Beta note",
        "Gamma doc",
      ].entries()) {
        await knowledge.documents
          .create({
            organizationId: org,
            document: { title, scope: index < 3 ? "organization" : "user" },
          })
          .orThrow();
      }

      for (const [index, name] of [
        "Alpha set",
        "Alpha pack",
        "Beta set",
        "Beta pack",
        "Gamma set",
      ].entries()) {
        await knowledge.collections
          .create({
            organizationId: org,
            collection: {
              name,
              priority: index,
              visibility: index < 3 ? "automatic" : "restricted",
            },
          })
          .orThrow();
      }

      await spreadTimes(s, "knowledge_documents", ["created_at", "updated_at"]);
      await spreadTimes(s, "knowledge_collections", ["created_at"]);
      await s.asRole(owner);

      await testBlockList({
        name: "knowledge.documents",
        target: {
          page: (options) =>
            knowledge.documents.page({ ...options, organizationId: org }),
          count: (options) =>
            knowledge.documents.count({ ...options, organizationId: org }),
          facets: (options) =>
            knowledge.documents.facets({ ...options, organizationId: org }),
          get: (id) => knowledge.documents.get(id),
        },
        rows: 5,
        sorts: ["createdAt", "title"],
        facets: { scope: { organization: 3, user: 2 }, status: { pending: 5 } },
        arrayFilter: { column: "scope", values: ["organization", "user"] },
        search: "Alpha",
      });

      await testBlockList({
        name: "knowledge.collections",
        target: {
          page: (options) =>
            knowledge.collections.page({ ...options, organizationId: org }),
          count: (options) =>
            knowledge.collections.count({ ...options, organizationId: org }),
          facets: (options) =>
            knowledge.collections.facets({ ...options, organizationId: org }),
          get: (id) => knowledge.collections.get(id),
        },
        rows: 5,
        sorts: ["priority", "name", "createdAt"],
        facets: { visibility: { automatic: 3, restricted: 2 } },
        arrayFilter: {
          column: "visibility",
          values: ["automatic", "restricted"],
        },
        search: "Alpha",
      });
    } finally {
      await s.close();
    }
  });

  it("pages knowledge documents and collections", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-chat", "ai-files", "knowledge"]);
      const owner = await s.user("knowledge-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const knowledge = createKnowledge({
        transport: sqlTransport(s.sql),
        embedder: wordEmbedder(),
        chunking: { size: 60, overlap: 0 },
      });

      const documents: string[] = [];

      for (const title of [
        "Alpha doc",
        "Alpha notes",
        "Beta doc",
        "Beta notes",
        "Gamma doc",
      ]) {
        const created = await knowledge.ingest
          .text({
            organizationId: org,
            document: { title, text: `${title} body text` },
          })
          .orThrow();

        documents.push(created.id);
      }

      await s.service();

      for (const id of documents.slice(0, 2)) {
        await knowledge.process({ documentId: id }).orThrow();
      }

      await s.asRole(owner);

      await testBlockList({
        name: "knowledge.documents",
        target: {
          page: (options) =>
            knowledge.documents.page({ ...options, organizationId: org }),
          count: (options) =>
            knowledge.documents.count({ ...options, organizationId: org }),
          facets: (options) =>
            knowledge.documents.facets({ ...options, organizationId: org }),
          get: (id) => knowledge.documents.get(id),
        },
        rows: 5,
        sorts: ["title"],
        facets: { status: { ready: 2, pending: 3 }, scope: { user: 5 } },
        arrayFilter: { column: "status", values: ["ready", "pending"] },
        search: "Alpha",
      });

      for (const [index, name] of [
        "Alpha set",
        "Alpha pack",
        "Beta set",
        "Beta pack",
        "Gamma set",
      ].entries()) {
        await knowledge.collections
          .create({
            organizationId: org,
            collection: {
              name,
              visibility: index < 2 ? "restricted" : "automatic",
              priority: index,
            },
          })
          .orThrow();
      }

      await testBlockList({
        name: "knowledge.collections",
        target: {
          page: (options) =>
            knowledge.collections.page({ ...options, organizationId: org }),
          count: (options) =>
            knowledge.collections.count({ ...options, organizationId: org }),
          facets: (options) =>
            knowledge.collections.facets({ ...options, organizationId: org }),
          get: (id) => knowledge.collections.get(id),
        },
        rows: 5,
        sorts: ["name", "priority"],
        facets: { visibility: { restricted: 2, automatic: 3 } },
        arrayFilter: {
          column: "visibility",
          values: ["restricted", "automatic"],
        },
        search: "Alpha",
      });
    } finally {
      await s.close();
    }
  });
});
