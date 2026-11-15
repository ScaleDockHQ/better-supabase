/* oxlint-disable typescript/no-deprecated -- these tests cover the deprecated aliases until 0.70 (ADR 1077). 8 findings. */
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createAgents } from "../../src/blocks/agents/index.ts";
import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createAiEvals } from "../../src/blocks/ai-evals/index.ts";
import { createAiFiles } from "../../src/blocks/ai-files/index.ts";
import { createAiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";
import { createAiKeys } from "../../src/blocks/ai-keys/index.ts";
import { createAiSchedules } from "../../src/blocks/ai-schedules/index.ts";
import { createChannels } from "../../src/blocks/channels/index.ts";
import { createInbox } from "../../src/blocks/inbox/index.ts";
import { createKnowledge } from "../../src/blocks/knowledge/index.ts";
import { createMemory } from "../../src/blocks/memory/index.ts";
import { createMessaging } from "../../src/blocks/messaging/index.ts";
import { createPosts } from "../../src/blocks/posts/index.ts";

const MINE = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";

const allowed = {
  organizationId: MINE,
  allowed: true,
  permission: "ai_chat.manage",
} as const;

/**
 * Answers `page_*` with an empty page, a facet read, or a count, and `get_*`
 * with nothing.
 */
function pages(): BlockTransport & { readonly fns: string[] } {
  const fns: string[] = [];

  return {
    fns,
    call: (_schema, fn, args) => {
      fns.push(fn);

      if (!fn.startsWith("page_")) {
        return Promise.resolve(null);
      }

      const filters = args["filters"];

      const record =
        typeof filters === "object" && filters !== null
          ? (filters as Record<string, unknown>)
          : {};

      if (record["facet"] !== undefined) {
        return Promise.resolve({ facet: record["facet"], values: [] });
      }

      return Promise.resolve(
        record["count"] === true
          ? { value: 0, exact: true }
          : { items: [], hasMore: false, nextCursor: null },
      );
    },
  };
}

const unusedStorage = {
  from: () => {
    throw new Error("storage is not used by a list");
  },
};

describe("the F11 and F12 list reads", () => {
  it("reads agents, keys, tasks, chats and files by page", async () => {
    const transport = pages();

    const agents = createAgents({ transport });
    await agents.page({ organizationId: MINE }).orThrow();
    await agents.facets({ organizationId: MINE }).orThrow();
    await agents.count({ organizationId: MINE }).orThrow();

    const keys = createAiKeys({ transport });
    await keys.keys.page({ organizationId: MINE }).orThrow();
    await keys.keys.facets({ organizationId: MINE }).orThrow();
    await keys.keys.count({ organizationId: MINE }).orThrow();
    await keys.batches.page({ organizationId: MINE }).orThrow();
    await keys.batches.facets({ organizationId: MINE }).orThrow();
    await keys.batches.count({ organizationId: MINE }).orThrow();

    const tasks = createAiSchedules({ transport });
    await tasks.page({ organizationId: MINE }).orThrow();
    await tasks.facets({ organizationId: MINE }).orThrow();
    await tasks.count({ organizationId: MINE }).orThrow();

    const chat = createAiChat({ transport });
    await chat.chats.page({ organizationId: MINE }).orThrow();
    await chat.chats.facets({ organizationId: MINE }).orThrow();
    await chat.chats.count({ organizationId: MINE }).orThrow();
    await chat.projects.page({ organizationId: MINE }).orThrow();
    await chat.projects.facets({ organizationId: MINE }).orThrow();
    await chat.projects.count({ organizationId: MINE }).orThrow();

    const files = createAiFiles({ transport, storage: unusedStorage });
    await files.files.page({ organizationId: MINE }).orThrow();
    await files.files.facets({ organizationId: MINE }).orThrow();
    await files.files.count({ organizationId: MINE }).orThrow();

    expect(new Set(transport.fns)).toEqual(
      new Set([
        "page_agents",
        "page_ai_provider_keys",
        "page_ai_batches",
        "page_ai_tasks",
        "page_ai_chats",
        "page_ai_projects",
        "page_ai_files",
      ]),
    );
  });

  it("reads knowledge, inbox, channels, messaging, posts and memory by page", async () => {
    const transport = pages();

    const knowledge = createKnowledge({ transport });
    await knowledge.documents.page({ organizationId: MINE }).orThrow();
    await knowledge.documents.facets({ organizationId: MINE }).orThrow();
    await knowledge.documents.count({ organizationId: MINE }).orThrow();
    await knowledge.collections.page({ organizationId: MINE }).orThrow();
    await knowledge.collections.facets({ organizationId: MINE }).orThrow();
    await knowledge.collections.count({ organizationId: MINE }).orThrow();

    const inbox = createInbox({ transport });
    await inbox.conversations.page({ organizationId: MINE }).orThrow();
    await inbox.conversations.facets({ organizationId: MINE }).orThrow();
    await inbox.conversations.count({ organizationId: MINE }).orThrow();

    const channels = createChannels({ transport, tenant: MINE });
    await channels.page().orThrow();
    await channels.facets().orThrow();
    await channels.count().orThrow();

    const messaging = createMessaging({ transport, tenant: MINE });
    await messaging.conversationPage().orThrow();
    await messaging.conversationFacets().orThrow();
    await messaging.conversationCount().orThrow();

    const posts = createPosts({ transport, tenant: MINE });
    await posts.page().orThrow();
    await posts.facets().orThrow();
    await posts.count().orThrow();
    await posts.boardPage().orThrow();
    await posts.boardFacets().orThrow();
    await posts.boardCount().orThrow();

    const memory = createMemory({ transport });
    await memory.archival.page({ organizationId: MINE }).orThrow();
    await memory.archival.facets({ organizationId: MINE }).orThrow();
    await memory.archival.count({ organizationId: MINE }).orThrow();

    expect(transport.fns).toContain("page_memories");
    expect(transport.fns).toContain("page_inbox_conversations");
    expect(transport.fns).toContain("page_channels");
    expect(transport.fns).toContain("page_conversations");
    expect(transport.fns).toContain("page_posts");
    expect(transport.fns).toContain("page_post_boards");
  });

  it("returns not_found when a single read finds nothing", async () => {
    const transport = pages();

    const results = await Promise.all([
      createAgents({ transport }).get("a1"),
      createAiKeys({ transport }).keys.get("k1"),
      createAiKeys({ transport }).batches.getBatch("b1"),
      createAiSchedules({ transport }).get("t1"),
      createAiChat({ transport }).chats.get("c1"),
      createAiChat({ transport }).projects.get("p1"),
      createInbox({ transport }).conversations.getConversation("c1"),
      createChannels({ transport, tenant: MINE }).getChannel("c1"),
      createPosts({ transport, tenant: MINE }).getPost("p1"),
      createMemory({ transport }).archival.get("m1"),
      createKnowledge({ transport }).documents.get("d1"),
      createKnowledge({ transport }).collections.get("c1"),
    ]);

    for (const result of results) {
      expect(result.ok).toBe(false);
    }
  });

  it("scopes evals and guardrails pages to the caller's organization", async () => {
    const transport = pages();
    const evals = createAiEvals({ transport, access: allowed });

    await evals.datasets.page({ organizationId: MINE }).orThrow();
    await evals.datasets.facets({ organizationId: MINE }).orThrow();
    await evals.datasets.count({ organizationId: MINE }).orThrow();
    await evals.runs.page({ organizationId: MINE }).orThrow();
    await evals.runs.facets({ organizationId: MINE }).orThrow();
    await evals.runs.count({ organizationId: MINE }).orThrow();

    const guardrails = createAiGuardrails({ transport, access: allowed });

    await guardrails.policies.page({ organizationId: MINE }).orThrow();
    await guardrails.policies.facets({ organizationId: MINE }).orThrow();
    await guardrails.policies.count({ organizationId: MINE }).orThrow();
    await guardrails.decisions.page({ organizationId: MINE }).orThrow();
    await guardrails.decisions.facets({ organizationId: MINE }).orThrow();
    await guardrails.decisions.count({ organizationId: MINE }).orThrow();

    const calls = transport.fns.length;

    const refused = await Promise.all([
      evals.datasets.page({ organizationId: OTHER }),
      evals.datasets.facets({ organizationId: OTHER }),
      evals.datasets.count({ organizationId: OTHER }),
      evals.runs.page({ organizationId: OTHER }),
      evals.runs.facets({ organizationId: OTHER }),
      evals.runs.count({ organizationId: OTHER }),
      guardrails.policies.page({ organizationId: OTHER }),
      guardrails.policies.facets({ organizationId: OTHER }),
      guardrails.policies.count({ organizationId: OTHER }),
      guardrails.decisions.page({ organizationId: OTHER }),
      guardrails.decisions.facets({ organizationId: OTHER }),
      guardrails.decisions.count({ organizationId: OTHER }),
    ]);

    for (const result of refused) {
      expect(result.error?.kind).toBe("forbidden");
    }

    expect(transport.fns).toHaveLength(calls);
  });

  it("reads one eval dataset, run and policy as not found when absent", async () => {
    const transport = pages();
    const evals = createAiEvals({ transport, access: allowed });
    const guardrails = createAiGuardrails({ transport, access: allowed });

    expect((await evals.datasets.getDataset("d1")).ok).toBe(false);
    expect((await evals.runs.getRun("r1")).ok).toBe(false);
    expect((await guardrails.policies.getPolicy("p1")).ok).toBe(false);
    expect(
      (await createAiEvals({ transport }).datasets.getDataset("d1")).ok,
    ).toBe(false);
  });

  it("keeps the deprecated list and get aliases behind the same access check", async () => {
    const transport: BlockTransport = { call: () => Promise.resolve([]) };

    const evals = createAiEvals({ transport, access: allowed });
    const guardrails = createAiGuardrails({ transport, access: allowed });

    expect(
      (await evals.datasets.list({ organizationId: OTHER })).error?.kind,
    ).toBe("forbidden");
    expect((await evals.datasets.get("d1")).ok).toBe(false);
    expect((await evals.runs.get("r1")).ok).toBe(false);
    expect((await evals.runs.list({ datasetId: "d1" })).ok).toBe(false);
    expect(
      (await guardrails.policies.list({ organizationId: OTHER })).error?.kind,
    ).toBe("forbidden");
    expect(
      (await guardrails.decisions.list({ organizationId: OTHER })).error?.kind,
    ).toBe("forbidden");
    expect(
      (
        await guardrails.policies.get({
          agent: "*",
          stage: "input",
          organizationId: OTHER,
        })
      ).error?.kind,
    ).toBe("forbidden");
  });
});
