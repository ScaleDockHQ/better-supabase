import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

const folder = new URL("schemas/", import.meta.url);

describe("vendored schemas", () => {
  it("match the SHA-256 recorded in SOURCES.md and nothing is unlisted", async () => {
    const sources = await readFile(new URL("SOURCES.md", folder), "utf8");
    const pinned = new Map(
      [
        ...sources.matchAll(
          /^\| `([^`]+\.(?:json|sql))` \|.*\| `([0-9a-f]{64})` \|$/gm,
        ),
      ].map((match) => [match[1]!, match[2]!]),
    );
    const files = (await readdir(folder)).filter(
      (file) => file !== "SOURCES.md",
    );
    expect(files.toSorted()).toEqual([...pinned.keys()].toSorted());
    const digests = new Map<string, string>();
    for (const file of files) {
      digests.set(
        file,
        createHash("sha256")
          .update(await readFile(new URL(file, folder)))
          .digest("hex"),
      );
    }
    expect(Object.fromEntries(digests)).toEqual(Object.fromEntries(pinned));
  });
});
