import { describe, expect, it, vi } from "vitest";

import { commentsBlock } from "../../src/blocks/comments/manifest.ts";
import { customFieldsBlock } from "../../src/blocks/custom-fields/manifest.ts";
import { defineBlock } from "../../src/blocks/define-block.ts";
import { driveBlock } from "../../src/blocks/drive/manifest.ts";
import { fieldHistoryBlock } from "../../src/blocks/field-history/manifest.ts";
import { reactionsBlock } from "../../src/blocks/reactions/manifest.ts";
import { signaturesBlock } from "../../src/blocks/signatures/manifest.ts";
import { tagsBlock } from "../../src/blocks/tags/manifest.ts";
import { versionsBlock } from "../../src/blocks/versions/manifest.ts";
import {
  copyBindings,
  copyableBindings,
  defineRecordBinding,
} from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const from = { type: "customer", id: "1" };
const to = { type: "customer", id: "2" };

const copy = vi.fn((_client: object, _from: object, _to: object) =>
  resolved(3),
);

const copying = defineBlock({
  name: "copying",
  category: "work",
  create: () => ({}),
  record: defineRecordBinding({
    permissions: { read: "read" },
    load: () => resolved(0),
    copy,
    events: [],
  }),
});

const readOnly = defineBlock({
  name: "readonly",
  category: "work",
  create: () => ({}),
  record: defineRecordBinding({
    permissions: { read: "read" },
    load: () => resolved(0),
    events: [],
  }),
});

const broken = defineBlock({
  name: "broken",
  category: "work",
  create: () => ({}),
  record: defineRecordBinding({
    permissions: { read: "read" },
    load: () => resolved(0),
    copy: () => failed<number>("No copy"),
    events: [],
  }),
});

describe("copyBindings", () => {
  const blocks = { copying, readOnly, broken };
  const clients = { copying: {}, readOnly: {}, broken: {} };

  it("lists the bindings that can copy", () => {
    expect(copyableBindings(blocks)).toEqual(["copying", "broken"]);
  });

  it("returns the count each binding copied", async () => {
    const result = await copyBindings({ blocks, clients }, from, to, [
      "copying",
    ]);

    expect(result).toMatchObject({ ok: true, data: { copying: 3 } });
    expect(copy).toHaveBeenCalledWith(clients.copying, from, to);
  });

  it("stops at the first binding that fails", async () => {
    const result = await copyBindings({ blocks, clients }, from, to);

    expect(result.ok).toBe(false);
  });

  it("refuses a binding without a copy", async () => {
    const result = await copyBindings({ blocks, clients }, from, to, [
      "readOnly",
    ]);

    expect(result).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
  });
});

describe("the shipped bindings", () => {
  it("copy tags, comments and custom fields only", () => {
    expect(
      copyableBindings({
        tags: tagsBlock,
        comments: commentsBlock,
        customFields: customFieldsBlock,
        fieldHistory: fieldHistoryBlock,
        reactions: reactionsBlock,
        drive: driveBlock,
        signatures: signaturesBlock,
        versions: versionsBlock,
      }),
    ).toEqual(["tags", "comments", "customFields"]);
  });
});
