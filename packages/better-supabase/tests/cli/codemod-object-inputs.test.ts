import { describe, expect, it } from "vitest";

import {
  findObjectInputCalls,
  OBJECT_INPUT_COUNT,
  rewriteObjectInputCalls,
} from "../../src/cli/codemod-object-inputs.ts";

const rewrite = (source: string): string =>
  rewriteObjectInputCalls(source).text;

describe("rewriteObjectInputCalls", () => {
  it("rewrites a sub-client call to one object", () => {
    expect(rewrite("await chats.runs.setCost(id, 120, usage);")).toBe(
      "await chats.runs.setCost({ generationId: id, costMicroUsd: 120, usage });",
    );
  });

  it("merges an options object flat and spreads other options", () => {
    expect(
      rewrite("await chats.runs.claim(chatId, streamId, { engine });"),
    ).toBe("await chats.runs.claim({ chatId, streamId, engine });");
    expect(rewrite("await chats.runs.claim(chatId, streamId, opts);")).toBe(
      "await chats.runs.claim({ chatId, streamId, ...opts });",
    );
  });

  it("drops an undefined optional argument", () => {
    expect(
      rewrite("await chats.runs.claim(chatId, streamId, undefined);"),
    ).toBe("await chats.runs.claim({ chatId, streamId });");
  });

  it("rewrites inner calls before the call that holds them", () => {
    expect(
      rewrite("await chats.runs.attach(id, await chats.runs.attach(a, b));"),
    ).toContain("attach({ runId: id, externalRunId: await");
  });

  it("leaves a call that already takes one object alone", () => {
    const source = "await chats.runs.claim({ chatId, streamId });";

    expect(rewriteObjectInputCalls(source)).toEqual({
      text: source,
      review: [],
    });
  });

  it("ignores strings and comments", () => {
    const source =
      '// chats.runs.setCost(id, 1, usage)\nconst s = "chats.runs.setCost(a, b, c)";';

    expect(rewrite(source)).toBe(source);
  });

  it("lists a call whose receiver it can't place", () => {
    const result = rewriteObjectInputCalls("thing.setCost(id, 1, usage);");

    expect(result.text).toBe("thing.setCost(id, 1, usage);");
    expect(result.review).toHaveLength(1);
  });

  it("finds the same candidates the doctor reports", () => {
    expect(findObjectInputCalls("thing.setCost(id, 1, usage);")).toHaveLength(
      1,
    );
    expect(OBJECT_INPUT_COUNT).toBeGreaterThan(1000);
  });
});
