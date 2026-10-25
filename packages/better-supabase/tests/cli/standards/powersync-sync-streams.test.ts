import { describe, expect, it } from "vitest";
import { parse } from "yaml";

import { powersyncOutput } from "../../../src/cli/powersync/streams.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { SPEC_PINS } from "../../../src/core/spec-pins.ts";
import { moduleLayout, renderBlocks } from "../../../src/sql/index.ts";

const config = resolveConfig(
  { blocks: { memberships: {}, notifications: {}, attachments: {} } },
  "/p",
);

const { streams } = powersyncOutput({
  files: renderBlocks(config.blockNames, moduleLayout(config)),
  instances: [
    { key: "notifications", block: "notifications" },
    { key: "attachments", block: "attachments" },
  ],
  importFrom: "@powersync/common",
});

interface StreamsDocument {
  readonly config: { readonly edition: number };
  readonly streams: Readonly<
    Record<string, { readonly auto_subscribe: boolean; readonly query: string }>
  >;
}

// SAFETY: the test checks every field it reads below.
const document = parse(streams) as StreamsDocument;

describe("PowerSync sync streams", () => {
  it("declares the pinned config edition", () => {
    expect(String(document.config.edition)).toBe(
      SPEC_PINS.powersyncSyncStreams,
    );
  });

  it("gives each stream one query and auto_subscribe, and no other key", () => {
    for (const stream of Object.values(document.streams)) {
      expect(Object.keys(stream).toSorted()).toEqual([
        "auto_subscribe",
        "query",
      ]);

      expect(stream.auto_subscribe).toBe(true);
    }
  });

  it("selects whole rows from one table, scoped to the user with auth.user_id()", () => {
    for (const { query } of Object.values(document.streams)) {
      expect(query).toMatch(/^SELECT \* FROM [a-z_]+\.[a-z_]+ WHERE /);
      expect(query).toContain("auth.user_id()");
      expect(query).not.toMatch(/\bJOIN\b|;/i);
    }
  });
});
