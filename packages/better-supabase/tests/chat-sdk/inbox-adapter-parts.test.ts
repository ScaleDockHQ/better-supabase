import { describe, expect, it } from "vitest";

import {
  byteLength,
  emojiFromRaw,
  outgoingFilesOf,
} from "../../src/chat-sdk/inbox-adapter-parts.ts";

describe("outgoingFilesOf", () => {
  it("returns nothing for a plain string", async () => {
    expect(await outgoingFilesOf("hi")).toEqual([]);
  });

  it("collects files and attachment bytes, fetching them when needed", async () => {
    const data = Buffer.from("abc");

    const files = await outgoingFilesOf({
      markdown: "x",
      files: [{ filename: "a.txt", mimeType: "text/plain", data }],
      attachments: [
        { type: "file", name: "b.bin", data },
        { type: "file", fetchData: async () => Buffer.from("zz") },
        { type: "file" },
      ],
    });

    expect(files.map((file) => file.name)).toEqual(["a.txt", "b.bin", "file"]);
  });
});

describe("byteLength and emojiFromRaw", () => {
  it("measures blobs and buffers", () => {
    expect(byteLength(new Blob(["abcd"]))).toBe(4);
    expect(byteLength(new ArrayBuffer(2))).toBe(2);
  });

  it("resolves short names and raw emoji", () => {
    expect(String(emojiFromRaw("thumbsup"))).toBeTruthy();
    expect(String(emojiFromRaw("👍"))).toBeTruthy();
  });
});
