import { describe, expect, it, vi } from "vitest";

import type { BlockContext } from "../../src/blocks/index.ts";

import { entityFlagHooks } from "../../src/blocks/entity-flags.ts";
import { createBlocks, defineBlock } from "../../src/blocks/index.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { AsyncResult } from "../../src/core/result.ts";

const info = { block: "notes", method: "list" };

describe("entityFlagHooks", () => {
  it("hooks only the methods of an entity that names a flag", () => {
    const hooks = entityFlagHooks(
      {
        note: { flag: "notes", methods: ["list", "create"] },
        tag: { methods: ["tags"] },
        pin: { flag: "pins" },
      },
      () => true,
    );

    expect(Object.keys(hooks).toSorted()).toStrictEqual(["create", "list"]);
  });

  it("refuses with not_found while the flag is off and passes when it is on", async () => {
    const enabled = new Set<string>();
    const check = vi.fn((key: string) => enabled.has(key));

    const { list } = entityFlagHooks(
      { note: { flag: "notes", methods: ["list"] } },
      check,
    );

    expect(await list?.before?.([], info)).toMatchObject({
      kind: "not_found",
      message: "note is not available",
    });

    enabled.add("notes");
    expect(await list?.before?.([], info)).toBeUndefined();
  });

  it("counts a throwing check as off and needs every flag of a shared method", async () => {
    const { list } = entityFlagHooks(
      {
        note: { flag: "notes", methods: ["list"] },
        memo: { flag: "memos", methods: ["list"] },
      },
      (key) => {
        if (key === "memos") {
          throw new Error("flags are down");
        }

        return true;
      },
    );

    expect(await list?.before?.([], info)).toMatchObject({
      kind: "not_found",
      message: "memo is not available",
    });
  });
});

describe("createBlocks flags", () => {
  const transport = {
    call: vi.fn(() => Promise.resolve({ data: null, error: null })),
  };

  const notesBlock = defineBlock({
    name: "notes",
    create: (_options: BlockContext) => ({
      list: vi.fn(() => AsyncResult.ok("listed")),
      open: vi.fn(() => AsyncResult.ok("opened")),
    }),
    entities: {
      note: { mutability: "editable", flag: "notes", methods: ["list"] },
    },
    category: "work",
  });

  it("hides the declared methods only when `flags` is given and the flag is off", async () => {
    const plain = createBlocks({ transport }, { notes: notesBlock });

    expect(await plain.notes.list()).toMatchObject({ ok: true });

    const off = createBlocks(
      { transport, flags: () => false },
      { notes: notesBlock },
    );

    expect(await off.notes.list()).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
    expect(await off.notes.open()).toMatchObject({ ok: true });

    const on = createBlocks(
      { transport, flags: (key) => key === "notes" },
      { notes: notesBlock },
    );

    expect(await on.notes.list()).toMatchObject({ ok: true });
  });
});

describe("the flags shipped manifests declare", () => {
  it("lists the methods of every entity that names a flag", () => {
    const wrong = BLOCK_MANIFESTS.flatMap((block) =>
      Object.entries(block.entities ?? {}).flatMap(([key, surface]) =>
        surface.flag !== undefined && (surface.methods ?? []).length === 0
          ? [`${block.name}.${key}`]
          : [],
      ),
    );

    expect(wrong).toStrictEqual([]);
  });
});
