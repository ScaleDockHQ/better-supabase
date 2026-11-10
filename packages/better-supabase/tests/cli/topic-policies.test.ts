import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { ResolvedConfig } from "../../src/config/index.ts";

import { topicPolicyFile } from "../../src/cli/topic-policies.ts";

const root = join(import.meta.dirname, "fixtures/topics");

const config = (blockNames: string[]): ResolvedConfig =>
  // SAFETY: topicPolicyFile reads only root, realtime, authorization and blockNames.
  ({
    root,
    blockNames,
    realtime: {
      policies: { from: ["broadcast-topic.mjs"], file: "905_topics.sql" },
      triggers: [],
    },
  }) as unknown as ResolvedConfig;

describe("topic-declared broadcast triggers (ADR 0663)", () => {
  it("writes the triggers of a topic's broadcast option next to its policies", async () => {
    const file = await topicPolicyFile(config(["realtime-tables"]));

    expect(file?.path).toBe("905_topics.sql");
    expect(file?.contents).toContain("create policy");
    expect(file?.contents).toContain("public.orders");
    expect(file?.contents).toContain("broadcast_topic");
    expect(file?.contents).toContain("public.order_lines");
  });

  it("needs realtime-tables for a trigger that calls broadcast_topic", async () => {
    await expect(topicPolicyFile(config([]))).rejects.toThrow(
      /defineTopic\("org:\{organizationId\}:orders"\)\.broadcast\[0\].*realtime-tables/u,
    );
  });
});
