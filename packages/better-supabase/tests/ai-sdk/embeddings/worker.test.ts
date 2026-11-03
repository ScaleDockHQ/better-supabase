import { describe, expect, it } from "vitest";

import { embeddingWorker } from "../../../src/ai-sdk/embeddings/worker.ts";

const embedder = {
  model: "m",
  embed: async (values: readonly string[]) => values.map((v) => [v.length]),
};

function post(body: unknown, token = "tok") {
  return new Request("https://x.test/w", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

const job = (id: string, content: string, readCount = 1) => ({
  msgId: 1,
  readCount,
  id,
  content,
  hash: "h",
});

describe("embeddingWorker", () => {
  it("embeds a batch, skipping empty and over-read jobs", async () => {
    const applied: [string, number[]][] = [];

    const worker = embeddingWorker({
      embedder,
      token: "tok",
      apply: async (_batch, j, vector) => {
        applied.push([j.id, [...vector]]);

        return j.id !== "stale";
      },
    });

    const response = await worker(
      post({
        queue: "q",
        table: "t",
        jobs: [
          job("a", "abc"),
          job("stale", "xy"),
          job("empty", "  "),
          job("poison", "zz", 9),
        ],
      }),
    );

    expect(await response.json()).toEqual({
      embedded: 1,
      stale: 1,
      skipped: 2,
    });
    expect(applied).toEqual([
      ["a", [3]],
      ["stale", [2]],
    ]);
  });

  it("rejects a wrong token and a bad body", async () => {
    const worker = embeddingWorker({
      embedder,
      token: "tok",
      apply: async () => true,
    });

    expect((await worker(post({}, "nope"))).status).toBe(401);
    expect((await worker(post({ nope: 1 }))).status).toBe(400);
  });

  it("answers 500 when embedding fails", async () => {
    const worker = embeddingWorker({
      embedder: {
        model: "m",
        embed: async () => {
          throw new Error("down");
        },
      },
      token: "tok",
      apply: async () => true,
    });

    const response = await worker(
      post({ queue: "q", table: "t", jobs: [job("a", "x")] }),
    );

    expect(response.status).toBe(500);
  });
});
