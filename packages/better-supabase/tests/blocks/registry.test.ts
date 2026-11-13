import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { FORMER_BLOCK_NAMES } from "../../src/sql/former-block-names.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

/**
 * SQL modules a block installs next to the module of its own name, by module.
 * The list only shrinks (ADR 0699): a block has one key, and a module under
 * another name is a second part of that block.
 */
const SECOND_MODULES: Readonly<Record<string, string>> = {
  "chat-sdk-state": "inbox",
  "drive-files": "drive",
  housekeeping: "queue",
  invitations: "organizations",
  recurrence: "reminders",
  seeds: "organizations",
};

describe("one key per block", () => {
  it("names every SQL module after its block unless it is a second part of one", () => {
    const stray = BLOCK_MANIFESTS.flatMap((block) =>
      block.sql
        .filter(
          (module) =>
            module !== block.name && SECOND_MODULES[module] !== block.name,
        )
        .map((module) => `${block.name} installs ${module}`),
    );

    expect(stray).toEqual([]);
  });

  it("lists only second modules a block still installs", () => {
    const stale = Object.entries(SECOND_MODULES).filter(
      ([module, owner]) =>
        !BLOCK_MANIFESTS.some(
          (block) => block.name === owner && block.sql.includes(module),
        ),
    );

    expect(stale).toEqual([]);
  });

  it("keeps no SQL module or manifest under a name the block had before", () => {
    const names = new Set([
      ...BLOCK_MANIFESTS.map((block) => block.name),
      ...Object.keys(SQL_MODULES),
    ]);

    const kept = [...FORMER_BLOCK_NAMES.values()].filter((former) =>
      names.has(former),
    );

    expect(kept).toEqual([]);
  });

  it("renamed the webhooks family to the names of its blocks", () => {
    expect(FORMER_BLOCK_NAMES.get("webhooks")).toBe("webhooks-out");
    expect(FORMER_BLOCK_NAMES.get("incoming-webhooks")).toBe("webhooks-in");
  });
});
