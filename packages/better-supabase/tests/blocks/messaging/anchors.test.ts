import { describe, expect, it } from "vitest";

import {
  createMessaging,
  fileAnchor,
  isFileAnchor,
} from "../../../src/blocks/messaging/index.ts";

const FILE = "00000000-0000-4000-8000-0000000f1001";
const AT = "2026-10-22T10:00:00Z";

describe("fileAnchor", () => {
  it("builds an anchor on a page, region and span", () => {
    expect(
      fileAnchor(FILE, {
        page: 3,
        region: { x: 0.1, y: 0.2, width: 0.5, height: 0.1 },
      }),
    ).toEqual({
      kind: "file",
      attachmentId: FILE,
      page: 3,
      region: { x: 0.1, y: 0.2, width: 0.5, height: 0.1 },
    });
    expect(fileAnchor(FILE, { start: 0, end: 4.5 })).toMatchObject({
      start: 0,
      end: 4.5,
    });
    expect(fileAnchor(FILE)).toEqual({ kind: "file", attachmentId: FILE });
  });

  it.each([
    ["a page below 1", { page: 0 }],
    ["a fractional page", { page: 1.5 }],
    [
      "a region past the edge",
      { region: { x: 0.8, y: 0, width: 0.5, height: 0.1 } },
    ],
    ["an empty region", { region: { x: 0, y: 0, width: 0, height: 0.1 } }],
    ["a negative start", { start: -1 }],
    ["an end without a start", { end: 3 }],
    ["an end before the start", { start: 5, end: 5 }],
  ])("refuses %s", (_name, at) => {
    expect(() => fileAnchor(FILE, at)).toThrow(TypeError);
  });

  it("refuses an attachment id that isn't a uuid", () => {
    expect(() => fileAnchor("f1")).toThrow(TypeError);
  });
});

describe("isFileAnchor", () => {
  it("tells file anchors from other anchors", () => {
    expect(isFileAnchor({ kind: "file", attachmentId: FILE, page: 2 })).toBe(
      true,
    );
    expect(isFileAnchor({ from: 4, to: 9 })).toBe(false);
    expect(isFileAnchor(null)).toBe(false);
    expect(isFileAnchor([FILE])).toBe(false);
    expect(
      isFileAnchor({ kind: "file", attachmentId: FILE, region: "top" }),
    ).toBe(false);
    expect(
      isFileAnchor({
        kind: "file",
        attachmentId: FILE,
        region: { x: 0, y: 0, width: Number.NaN, height: 1 },
      }),
    ).toBe(false);
  });
});

describe("messaging.anchoredTo", () => {
  it("lists the messages anchored to a file", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const messaging = createMessaging({
      transport: {
        call(_schema, fn, args) {
          calls.push([fn, { ...args }]);

          return Promise.resolve([
            {
              id: "m1",
              tenant_id: "org",
              conversation_id: "c1",
              parent_id: null,
              thread_id: null,
              author_id: "u1",
              body: "Check this",
              document: null,
              anchor: { kind: "file", attachmentId: FILE, page: 3 },
              mentions: [],
              mention_scope: null,
              broadcast: false,
              scheduled_for: null,
              sent_at: AT,
              created_at: AT,
              edited_at: null,
              deleted_at: null,
              pinned_at: null,
              pinned_by: null,
              resolved_at: null,
              resolved_by: null,
              reply_count: 0,
              last_reply_at: null,
              files: [],
              reactions: [],
            },
          ]);
        },
      },
    });

    const messages = await messaging.anchoredTo(FILE, { limit: 10 }).orThrow();

    expect(calls).toEqual([
      ["list_file_anchors", { attachment: FILE, max_rows: 10 }],
    ]);
    expect(isFileAnchor(messages[0]?.anchor)).toBe(true);

    await messaging.anchoredTo(FILE).orThrow();
    expect(calls[1]?.[1]).toEqual({ attachment: FILE, max_rows: null });
  });
});
