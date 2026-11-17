import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { BLOCK_MEMO_MESSAGES } from "../../../src/blocks/messages/index.ts";

const MODULES = join(import.meta.dirname, "../../../src/sql/modules");

const KEY =
  /memo_key => '([a-z_.]+)'|'memoKey', '([a-z_.]+)'|"'?(accounting\.[a-z_]+)'?"/g;

function writtenKeys(): Set<string> {
  const keys = new Set<string>();

  for (const file of readdirSync(MODULES)) {
    const source = readFileSync(join(MODULES, file), "utf-8");

    for (const match of source.matchAll(KEY)) {
      const key = match[1] ?? match[2] ?? match[3];

      if (key) {
        keys.add(key);
      }
    }
  }

  return keys;
}

describe("BLOCK_MEMO_MESSAGES", () => {
  it("has a message for every memo key a module writes, and no other", () => {
    const written = [...writtenKeys()].filter(
      (key) => !/^accounting\.(read|write|post|close|manage)$/.test(key),
    );

    expect(written.toSorted()).toEqual(
      Object.keys(BLOCK_MEMO_MESSAGES).toSorted(),
    );
  });
});
