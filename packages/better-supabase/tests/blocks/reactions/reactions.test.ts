import { describe, expect, it } from "vitest";

import {
  createReactions,
  reactionsTopic,
} from "../../../src/blocks/reactions/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const C1 = { type: "comment", id: "c1" };

const COUNT = { emoji: "👍", count: 2, reacted: true, actors: ["u1", "bot"] };

const EMOJI = {
  id: "e1",
  shortcode: "ship-it",
  attachmentId: null,
  url: "https://cdn.test/ship.png",
  createdAt: "2026-10-01T00:00:00Z",
};

describe("reactions client", () => {
  it("reacts, reads summaries and manages custom emoji", async () => {
    const fake = transport({
      react: () => [COUNT],
      reaction_summary: () => ({ c1: [COUNT], c2: [] }),
      list_custom_emoji: () => [EMOJI],
      save_custom_emoji: () => EMOJI,
      delete_custom_emoji: () => true,
    });

    const reactions = createReactions({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    expect(
      await reactions.react({ subject: C1, emoji: "👍" }).orThrow(),
    ).toEqual([COUNT]);
    await reactions
      .react({ subject: C1, emoji: "👍", present: false, actor: "bot" })
      .orThrow();
    expect(
      await reactions
        .summary([C1, { type: "comment", id: "c2" }, C1])
        .orThrow(),
    ).toEqual({ "comment:c1": [COUNT], "comment:c2": [] });
    const [listed] = await reactions.customEmoji().orThrow();
    expect(listed).toMatchObject({ id: "e1", url: EMOJI.url });
    expect(listed).not.toHaveProperty("attachmentId");
    expect(listed?.createdAt.toString()).toBe("2026-10-01T00:00:00Z");
    await reactions
      .saveCustomEmoji({ shortcode: "ship-it", url: EMOJI.url })
      .orThrow();
    expect(await reactions.deleteCustomEmoji("e1").orThrow()).toBe(true);
    expect(fake.calls).toEqual([
      [
        "react",
        {
          tenant: "o",
          subject_type: "comment",
          subject_id: "c1",
          emoji: "👍",
          present: true,
          actor: null,
        },
      ],
      [
        "react",
        {
          tenant: "o",
          subject_type: "comment",
          subject_id: "c1",
          emoji: "👍",
          present: false,
          actor: "bot",
        },
      ],
      [
        "reaction_summary",
        { tenant: "o", subject_type: "comment", subject_ids: ["c1", "c2"] },
      ],
      ["list_custom_emoji", { tenant: "o" }],
      [
        "save_custom_emoji",
        {
          tenant: "o",
          shortcode: "ship-it",
          attachment_id: null,
          url: EMOJI.url,
        },
      ],
      ["delete_custom_emoji", { emoji_id: "e1" }],
    ]);
  });

  it("keys a summary of many types by type:id", async () => {
    const fake = transport({
      reaction_summary: (args) =>
        (args as { subject_type: string }).subject_type === "comment"
          ? { c1: [COUNT] }
          : { t1: [] },
    });

    const reactions = createReactions({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    expect(
      await reactions.summary([C1, { type: "task", id: "t1" }]).orThrow(),
    ).toEqual({ "comment:c1": [COUNT], "task:t1": [] });
    expect(fake.calls.map(([, args]) => args)).toEqual([
      { tenant: "o", subject_type: "comment", subject_ids: ["c1"] },
      { tenant: "o", subject_type: "task", subject_ids: ["t1"] },
    ]);
  });

  it("votes and reads vote tallies by subject", async () => {
    const fake = transport({
      vote: () => ({ score: 2, up: 3, down: 1, vote: -1 }),
      vote_summary: (args) =>
        (args as { subject_type: string }).subject_type === "comment"
          ? { c1: { score: 1, up: 1, down: 0, vote: 1 } }
          : { t1: { vote: "x" } },
    });

    const reactions = createReactions({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    expect(await reactions.vote({ subject: C1, value: -1 }).orThrow()).toEqual({
      score: 2,
      up: 3,
      down: 1,
      vote: -1,
    });
    await reactions.vote({ subject: C1, value: 0, actor: "bot" }).orThrow();
    expect(
      await reactions.votes([C1, { type: "task", id: "t1" }]).orThrow(),
    ).toEqual({
      "comment:c1": { score: 1, up: 1, down: 0, vote: 1 },
      "task:t1": { score: 0, up: 0, down: 0, vote: 0 },
    });
    expect(fake.calls.slice(0, 2)).toEqual([
      [
        "vote",
        {
          tenant: "o",
          subject_type: "comment",
          subject_id: "c1",
          value: -1,
          actor: null,
        },
      ],
      [
        "vote",
        {
          tenant: "o",
          subject_type: "comment",
          subject_id: "c1",
          value: 0,
          actor: "bot",
        },
      ],
    ]);
  });

  it("reads a custom emoji stored as an attachment", async () => {
    const stored = {
      id: "e2",
      shortcode: "logo",
      attachmentId: "a1",
      createdAt: EMOJI.createdAt,
    };

    const fake = transport({ save_custom_emoji: () => stored });

    const reactions = createReactions({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    const saved = await reactions
      .saveCustomEmoji({ shortcode: "logo", attachmentId: "a1" })
      .orThrow();

    expect(saved).toMatchObject({ id: "e2", attachmentId: "a1" });
    expect(saved).not.toHaveProperty("url");
    expect(fake.calls).toEqual([
      [
        "save_custom_emoji",
        { tenant: "o", shortcode: "logo", attachment_id: "a1", url: null },
      ],
    ]);
  });

  it("fails without a tenant", async () => {
    const fake = transport({ react: () => [COUNT] });
    const session: { tenant?: string } = {};

    const reactions = createReactions({
      transport: fake,
      schema: "app",
      tenant: () => session.tenant,
    });

    expect(await reactions.react({ subject: C1, emoji: "👍" })).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(await reactions.customEmoji()).toMatchObject({ ok: false });
    expect(fake.calls).toHaveLength(0);
    session.tenant = "o";
    expect(
      await reactions.react({ subject: C1, emoji: "👍" }).orThrow(),
    ).toEqual([COUNT]);
  });

  it("names the topic", () => {
    expect(reactionsTopic("o")).toBe("reactions:o");
    expect(reactionsTopic("o", "emoji")).toBe("emoji:o");
  });
});
