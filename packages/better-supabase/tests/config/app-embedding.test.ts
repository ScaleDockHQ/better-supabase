import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";

const resolve = (embedding: unknown, columns?: Record<string, unknown>) =>
  resolveConfig(
    {
      appTables: {
        articles: {
          columns: {
            title: { type: "text" },
            body: { type: "text" },
            views: { type: "integer" },
            secret: { type: "text", encrypted: true },
            ...columns,
          },
          embedding,
        },
      },
      // SAFETY: the tests pass malformed options on purpose to reach the validation.
    } as never,
    "/app",
  );

describe("appTables embedding", () => {
  it("keeps a valid option", () => {
    const embedding = {
      content: ["title", "body"],
      dimensions: 1536,
      type: "vector" as const,
      schedule: "30 seconds",
      batch: 50,
    };

    expect(resolve(embedding).appTables["articles"]?.embedding).toEqual(
      embedding,
    );
  });

  it("refuses unknown, non-text and encrypted columns", () => {
    expect(() => resolve({ content: ["nope"], dimensions: 8 })).toThrow(
      "tables.articles.embedding.content",
    );
    expect(() => resolve({ content: ["views"], dimensions: 8 })).toThrow(
      "plain text column",
    );
    expect(() => resolve({ content: ["secret"], dimensions: 8 })).toThrow(
      "plain text column",
    );
  });

  it("refuses a column named embedding", () => {
    expect(() =>
      resolve(
        { content: ["title"], dimensions: 8 },
        { embedding: { type: "text" } },
      ),
    ).toThrow('"embedding"');
  });

  it("checks the size for the vector type", () => {
    expect(() => resolve({ content: ["title"], dimensions: 4001 })).toThrow(
      "1 to 4000 for halfvec",
    );
    expect(() =>
      resolve({ content: ["title"], dimensions: 2001, type: "vector" }),
    ).toThrow("1 to 2000 for vector");
  });

  it("refuses a bad schedule, batch and option", () => {
    const base = { content: ["title"], dimensions: 8 };

    expect(() => resolve({ ...base, schedule: "x'; --" })).toThrow("schedule");
    expect(() => resolve({ ...base, batch: 0 })).toThrow("batch");
    expect(() => resolve({ ...base, queue: "q" })).toThrow("not an option");
  });

  it("refuses a malformed option, content and type", () => {
    expect(() => resolve("yes")).toThrow("must be an object");
    expect(() => resolve({ content: [], dimensions: 8 })).toThrow("1 to 20");
    expect(() => resolve({ content: [1], dimensions: 8 })).toThrow("1 to 20");
    expect(() =>
      resolve({ content: ["title", "title"], dimensions: 8 }),
    ).toThrow("twice");
    expect(() => resolve({ content: ["nope"], dimensions: 8 })).toThrow(
      "not a column",
    );
    expect(() => resolve({ content: ["views"], dimensions: 8 })).toThrow(
      "plain text column",
    );
    expect(() => resolve({ content: ["secret"], dimensions: 8 })).toThrow(
      "plain text column",
    );
    expect(() =>
      resolve({ content: ["title"], dimensions: 8, type: "bit" }),
    ).toThrow('"vector" or "halfvec"');
    expect(() => resolve({ content: ["title"], dimensions: "8" })).toThrow(
      "whole number",
    );
    expect(() =>
      resolve(
        { content: ["title"], dimensions: 8 },
        { embedding: { type: "text" } },
      ),
    ).toThrow("rename your column");
  });
});
