import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAgents } from "../../src/blocks/agents/index.ts";
import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createAiFiles } from "../../src/blocks/ai-files/index.ts";
import { createAiKeys } from "../../src/blocks/ai-keys/index.ts";
import { createAiSchedules } from "../../src/blocks/ai-schedules/index.ts";
import { createKnowledge } from "../../src/blocks/knowledge/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

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

  it("pages provider keys, batches and scheduled tasks", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([
        "organizations",
        "credentials",
        "ai-keys",
        "ai-schedules",
      ]);
      const owner = await s.user("keys-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const transport = sqlTransport(s.sql);
      const keys = createAiKeys({ transport });
      const tasks = createAiSchedules({ transport });

      for (const [index, [provider, name]] of [
        ["anthropic", "Alpha key"],
        ["anthropic", "Alpha spare"],
        ["openai", "Beta key"],
        ["openai", "Beta spare"],
        ["google", "Gamma key"],
      ].entries()) {
        await s.value(
          "better_supabase.upsert_ai_provider_key($1, $2, $3::jsonb, $4, '{}'::jsonb, $5)",
          [
            org,
            provider,
            JSON.stringify({
              provider: "vault",
              secret: `k${index}`,
              tenant: org,
            }),
            name,
            index < 3,
          ],
        );
      }

      for (const [index, provider] of [
        "alpha",
        "alpha",
        "beta",
        "beta",
        "gamma",
      ].entries()) {
        await createAiKeys({ transport })
          .batches.record({
            organizationId: org,
            batch: {
              provider,
              reference: { id: `b${index}` },
              status: index < 3 ? "pending" : "completed",
            },
          })
          .orThrow();
      }

      for (const [index, title] of [
        "Alpha digest",
        "Alpha report",
        "Beta digest",
        "Beta report",
        "Gamma digest",
      ].entries()) {
        const created = await tasks
          .create({
            organizationId: org,
            task: { title, prompt: "Summarize", cron: "0 9 * * *" },
          })
          .orThrow();

        if (index >= 3) {
          await tasks
            .pause({ organizationId: org, taskId: created.id })
            .orThrow();
        }
      }

      await spreadTimes(s, "ai_provider_keys", ["created_at"]);
      await spreadTimes(s, "ai_batches", ["created_at"]);
      await spreadTimes(s, "ai_scheduled_tasks", ["created_at"]);
      await s.asRole(owner);

      await testBlockList({
        name: "ai-keys.keys",
        target: {
          page: (options) =>
            keys.keys.page({ ...options, organizationId: org }),
          count: (options) =>
            keys.keys.count({ ...options, organizationId: org }),
          facets: (options) =>
            keys.keys.facets({ ...options, organizationId: org }),
          get: (id) => keys.keys.get(id),
        },
        rows: 5,
        sorts: ["name", "createdAt"],
        facets: {
          provider: { anthropic: 2, openai: 2, google: 1 },
          enabled: { true: 3, false: 2 },
        },
        arrayFilter: { column: "provider", values: ["anthropic", "openai"] },
        search: "Alpha",
      });

      await testBlockList({
        name: "ai-keys.batches",
        target: {
          page: (options) =>
            keys.batches.page({ ...options, organizationId: org }),
          count: (options) =>
            keys.batches.count({ ...options, organizationId: org }),
          facets: (options) =>
            keys.batches.facets({ ...options, organizationId: org }),
          get: (id) => keys.batches.getBatch(id),
        },
        rows: 5,
        sorts: ["createdAt"],
        facets: {
          status: { pending: 3, completed: 2 },
          provider: { alpha: 2, beta: 2, gamma: 1 },
        },
        arrayFilter: { column: "provider", values: ["alpha", "beta"] },
      });

      await testBlockList({
        name: "ai-schedules.tasks",
        target: {
          page: (options) => tasks.page({ ...options, organizationId: org }),
          count: (options) => tasks.count({ ...options, organizationId: org }),
          facets: (options) =>
            tasks.facets({ ...options, organizationId: org }),
          get: (id) => tasks.get(id),
        },
        rows: 5,
        sorts: ["createdAt", "title"],
        facets: { enabled: { true: 3, false: 2 } },
        arrayFilter: { column: "enabled", values: ["true", "false"] },
        search: "Alpha",
      });
    } finally {
      await s.close();
    }
  });

  it("pages ai files", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "ai-chat", "ai-files"]);
      const owner = await s.user("files-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const files = createAiFiles({
        transport: sqlTransport(s.sql),
        storage: {
          from: () => ({
            createSignedUploadUrl: (path) =>
              Promise.resolve({
                data: { signedUrl: `https://storage.test/${path}`, token: "t" },
                error: null,
              }),
            createSignedUrl: (path) =>
              Promise.resolve({
                data: { signedUrl: `https://storage.test/${path}` },
                error: null,
              }),
            download: () =>
              Promise.resolve({
                data: new Blob([new Uint8Array([1])]),
                error: null,
              }),
            remove: () => Promise.resolve({ data: [], error: null }),
            upload: () => Promise.resolve({ data: {}, error: null }),
          }),
        },
      });

      for (const [index, [filename, mediaType]] of [
        ["alpha one.png", "image/png"],
        ["alpha two.png", "image/png"],
        ["beta three.pdf", "application/pdf"],
        ["beta four.pdf", "application/pdf"],
        ["gamma five.txt", "text/plain"],
      ].entries()) {
        const { file } = await files.files
          .upload({
            organizationId: org,
            file: {
              filename: filename ?? "",
              mediaType: mediaType ?? "",
              size: index + 1,
            },
          })
          .orThrow();

        if (index < 3) {
          await s.client.query("reset role");
          await s.client.query(
            "update better_supabase.ai_files set status = 'ready', uploaded_at = now() where id = $1",
            [file.id],
          );
          await s.asRole(owner);
        }
      }

      await spreadTimes(s, "ai_files", ["created_at"]);
      await s.asRole(owner);

      await testBlockList({
        name: "ai-files.files",
        target: {
          page: (options) =>
            files.files.page({ ...options, organizationId: org }),
          count: (options) =>
            files.files.count({ ...options, organizationId: org }),
          facets: (options) =>
            files.files.facets({ ...options, organizationId: org }),
          get: (id) => files.files.get(id),
        },
        rows: 5,
        sorts: ["createdAt", "filename", "size"],
        facets: {
          status: { ready: 3, pending: 2 },
          mediaType: { "image/png": 2, "application/pdf": 2, "text/plain": 1 },
        },
        arrayFilter: {
          column: "mediaType",
          values: ["image/png", "application/pdf"],
        },
        search: "alpha",
      });
    } finally {
      await s.close();
    }
  });

  it("pages ai chats and projects", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "ai-chat"]);
      const owner = await s.user("chat-owner");
      const org = await s.organization(owner);
      await s.asRole(owner);

      const chat = createAiChat({ transport: sqlTransport(s.sql) });

      for (const [index, title] of [
        "Alpha plan",
        "Alpha notes",
        "Beta plan",
        "Beta notes",
        "Gamma plan",
      ].entries()) {
        const created = await chat.chats
          .create({ organizationId: org, input: { title } })
          .orThrow();

        if (index < 2) {
          await chat.chats
            .update({ chatId: created.id, patch: { pinned: true } })
            .orThrow();
        }
      }

      for (const [index, name] of [
        "Alpha project",
        "Beta project",
        "Gamma project",
        "Delta project",
      ].entries()) {
        const created = await chat.projects
          .create({ organizationId: org, input: { name } })
          .orThrow();

        if (index === 0) {
          await chat.projects
            .update({ projectId: created.id, input: { pinned: true } })
            .orThrow();
        }
      }

      await spreadTimes(s, "ai_chats", [
        "last_message_at",
        "created_at",
        "updated_at",
      ]);
      await spreadTimes(s, "ai_projects", ["updated_at", "created_at"]);

      await testBlockList({
        name: "ai-chat.chats",
        target: {
          page: (options) =>
            chat.chats.page({ ...options, organizationId: org }),
          count: (options) =>
            chat.chats.count({ ...options, organizationId: org }),
          facets: (options) =>
            chat.chats.facets({ ...options, organizationId: org }),
          get: (id) => chat.chats.get(id),
        },
        rows: 5,
        sorts: ["lastMessageAt", "createdAt", "title"],
        facets: { pinned: { true: 2, false: 3 } },
        arrayFilter: { column: "pinned", values: ["true", "false"] },
        search: "Alpha",
      });

      await testBlockList({
        name: "ai-chat.projects",
        target: {
          page: (options) =>
            chat.projects.page({ ...options, organizationId: org }),
          count: (options) =>
            chat.projects.count({ ...options, organizationId: org }),
          facets: (options) =>
            chat.projects.facets({ ...options, organizationId: org }),
          get: (id) => chat.projects.get(id),
        },
        rows: 4,
        sorts: ["updatedAt", "name"],
        facets: { pinned: { true: 1, false: 3 } },
        arrayFilter: { column: "pinned", values: ["true", "false"] },
        search: "Alpha",
      });
    } finally {
      await s.close();
    }
  });
});
