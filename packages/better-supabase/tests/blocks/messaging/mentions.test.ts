import { describe, expect, it } from "vitest";

import { mentionsIn } from "../../../src/blocks/comments/index.ts";
import {
  mentionSegments,
  parseMentions,
  recordMention,
  userMention,
} from "../../../src/blocks/messaging/index.ts";

const ADA = "0b6f6d8e-3c1d-4a8e-9f00-1a2b3c4d5e6f";
const BOB = "1c7a7e9f-4d2e-4b9f-8a11-2b3c4d5e6f70";

describe("parseMentions", () => {
  it("reads users, records and the scope, in order and without repeats", () => {
    const body = `Hi @[Ada](user:${ADA}) and @[Bob](USER:${BOB.toUpperCase()}), see @[Acme renewal](subject:deal/d-1) and @[Ada](user:${ADA}) @here`;

    expect(parseMentions(body)).toEqual({
      users: [ADA, BOB],
      records: [{ type: "deal", id: "d-1" }],
      scope: "here",
    });
  });

  it("lets @channel win over @here and ignores look-alikes", () => {
    expect(parseMentions("@here then @channel").scope).toBe("channel");
    expect(parseMentions("@channel then @here").scope).toBe("channel");
    expect(
      parseMentions("mail me@here.com, @channels, @Here, @[x](subject:Deal/1)"),
    ).toEqual({ users: [], records: [], scope: undefined });
  });

  it("keeps a record mentioned twice once", () => {
    expect(
      parseMentions("@[a](subject:deal/1) @[b](subject:deal/1)").records,
    ).toEqual([{ type: "deal", id: "1" }]);
  });
});

describe("mentionSegments", () => {
  it("splits a body into text and chips", () => {
    expect(
      mentionSegments(
        `Ping @[Ada](user:${ADA}) about @[Acme](subject:company/c1) @channel.`,
      ),
    ).toEqual([
      { kind: "text", text: "Ping " },
      { kind: "user", name: "Ada", userId: ADA },
      { kind: "text", text: " about " },
      { kind: "record", name: "Acme", subject: { type: "company", id: "c1" } },
      { kind: "text", text: " " },
      { kind: "scope", scope: "channel" },
      { kind: "text", text: "." },
    ]);
  });

  it("returns one text segment for a body without mentions, none for an empty one", () => {
    expect(mentionSegments("plain")).toEqual([{ kind: "text", text: "plain" }]);
    expect(mentionSegments("")).toEqual([]);
    expect(mentionSegments("@here")).toEqual([
      { kind: "scope", scope: "here" },
    ]);
  });

  it("falls back to the kind when a name is blank", () => {
    expect(userMention(" ", ADA)).toBe(`@[user](user:${ADA})`);
    expect(recordMention("]", { type: "deal", id: "1" })).toBe(
      "@[deal](subject:deal/1)",
    );
  });
});

describe("mention markup", () => {
  it("writes user and record mentions the parser reads back", () => {
    const body = `${userMention("Ada [admin]", ADA)} ${recordMention("Acme\nrenewal", { type: "deal", id: "d1" })}`;

    expect(body).toBe(
      `@[Ada [admin](user:${ADA}) @[Acme renewal](subject:deal/d1)`,
    );
    expect(parseMentions(body)).toMatchObject({
      users: [ADA],
      records: [{ type: "deal", id: "d1" }],
    });
  });

  it("refuses a record that the markup can't carry", () => {
    expect(() => recordMention("x", { type: "Deal", id: "1" })).toThrow(
      TypeError,
    );
    expect(() => recordMention("x", { type: "deal", id: "a b" })).toThrow(
      TypeError,
    );
    expect(() => recordMention("x", { type: "deal", id: "" })).toThrow(
      TypeError,
    );
  });
});

describe("comments mentionsIn", () => {
  it("reads the users from the shared parser", () => {
    expect(mentionsIn(`@[Ada](${ADA}) @[Acme](subject:deal/1)`)).toEqual([ADA]);
  });
});
