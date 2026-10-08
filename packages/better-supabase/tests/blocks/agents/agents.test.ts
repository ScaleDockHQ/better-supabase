import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAgents } from "../../../src/blocks/agents/index.ts";

const AT = "2026-01-01T00:00:00Z";

const agentRow = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "o1",
  owner_id: "u1",
  slug: "writer",
  name: "Writer",
  description: "Writes",
  instructions: "Be brief",
  model: null,
  tools: ["search"],
  connector_ids: ["c1"],
  knowledge_scope: [{ scope: "agent" }, { scope: "organization", id: "o1" }],
  starters: ["Hi"],
  visibility: "organization",
  published_at: AT,
  install_count: 3,
  rating_count: 2,
  rating_sum: 9,
  installed: true,
  my_rating: 4,
  skills: [{ id: "s1", provider: "vercel", reference: { slug: "pdf" } }],
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

describe("createAgents", () => {
  it("maps rows, including ratings, scopes and skills", async () => {
    const { transport, calls } = fakeTransport({
      save_agent: () => agentRow(),
      get_agent: (args) => (args["id"] === "gone" ? null : agentRow()),
    });
    const agents = createAgents({ transport });
    const created = await agents
      .create("o1", {
        slug: "writer",
        name: "Writer",
        description: "Writes",
        instructions: "Be brief",
        model: null,
        tools: ["search"],
        connectorIds: ["c1"],
        knowledgeScopes: [{ scope: "agent" }],
        starters: ["Hi"],
      })
      .orThrow();
    expect(calls[0]).toEqual({
      fn: "save_agent",
      args: {
        tenant: "o1",
        id: undefined,
        fields: {
          slug: "writer",
          name: "Writer",
          description: "Writes",
          instructions: "Be brief",
          model: null,
          tools: ["search"],
          connector_ids: ["c1"],
          knowledge_scope: [{ scope: "agent" }],
          starters: ["Hi"],
        },
      },
    });
    expect(created.rating).toBe(4.5);
    expect(created.myRating).toBe(4);
    expect(created.knowledgeScopes).toEqual([
      { scope: "agent" },
      { scope: "organization", id: "o1" },
    ]);
    expect(created.skills).toEqual([
      { id: "s1", provider: "vercel", reference: { slug: "pdf" } },
    ]);
    expect(created.publishedAt?.toString()).toBe(AT);

    const missing = await agents.get("gone");
    expect(missing.ok ? undefined : missing.error.hint).toBe("AGENT_NOT_FOUND");
    expect((await agents.bySlug("o1", "writer").orThrow()).slug).toBe("writer");
    expect(calls.at(-1)?.args).toEqual({ tenant: "o1", slug: "writer" });
  });

  it("defaults sparse rows", async () => {
    const { transport } = fakeTransport({
      save_agent: () =>
        agentRow({
          owner_id: null,
          description: null,
          instructions: null,
          visibility: "bogus",
          rating_count: 0,
          rating_sum: 0,
          my_rating: null,
          knowledge_scope: null,
          skills: null,
          installed: undefined,
          created_at: new Date(AT),
        }),
    });
    const agent = await createAgents({ transport })
      .update("o1", "a1", {})
      .orThrow();
    expect(agent).toMatchObject({
      ownerId: undefined,
      description: "",
      visibility: "private",
      rating: undefined,
      myRating: undefined,
      installed: false,
      knowledgeScopes: [],
      skills: [],
    });
  });

  it("calls the store functions", async () => {
    const { transport, calls } = fakeTransport({
      list_agents: () => [agentRow()],
      publish_agent: () => agentRow({ visibility: "public" }),
      install_agent: () => true,
      rate_agent: () => agentRow(),
      set_agent_skills: () => 2,
      delete_agent: () => true,
    });
    const agents = createAgents({ transport, schema: "app" });
    expect(
      (
        await agents
          .list("o1", { filter: "store", search: "w", limit: 5 })
          .orThrow()
      ).map((agent) => agent.id),
    ).toEqual(["a1"]);
    expect((await agents.publish("a1", "public").orThrow()).visibility).toBe(
      "public",
    );
    expect(await agents.install("o1", "a1").orThrow()).toBe(true);
    await agents.install("o1", "a1", false);
    await agents.rate("a1", 5, "great");
    expect(
      await agents
        .setSkills("a1", [{ provider: "vercel", reference: { slug: "pdf" } }])
        .orThrow(),
    ).toBe(2);
    expect(await agents.remove("a1").orThrow()).toBe(true);
    expect(calls.map(({ fn, args }) => [fn, args])).toEqual([
      [
        "list_agents",
        { tenant: "o1", filter: "store", search: "w", max_rows: 5 },
      ],
      ["publish_agent", { id: "a1", visibility: "public" }],
      ["install_agent", { tenant: "o1", agent_id: "a1", installed: true }],
      ["install_agent", { tenant: "o1", agent_id: "a1", installed: false }],
      ["rate_agent", { agent_id: "a1", rating: 5, comment: "great" }],
      [
        "set_agent_skills",
        {
          agent_id: "a1",
          skills: {
            items: [{ provider: "vercel", reference: { slug: "pdf" } }],
          },
        },
      ],
      ["delete_agent", { id: "a1" }],
    ]);
  });
});
