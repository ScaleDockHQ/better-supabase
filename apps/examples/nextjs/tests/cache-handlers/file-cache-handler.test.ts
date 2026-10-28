import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createFileCacheHandler } from "../../cache-handlers/file-cache-handler.ts";

let dir = "";

beforeEach(async () => {
  dir = await mkdtemp(path.join(tmpdir(), "bsb-remote-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

function entry(body: string, tags: string[]) {
  return Promise.resolve({
    value: new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(body));
        controller.close();
      },
    }),
    tags,
    stale: 300,
    timestamp: Date.now(),
    expire: 3600,
    revalidate: 900,
  });
}

async function read(stream: ReadableStream<Uint8Array>) {
  return new Response(stream).text();
}

// Two handlers over one directory stand in for two `next start` instances.
describe("createFileCacheHandler", () => {
  it("serves one instance's entry to the other", async () => {
    const first = createFileCacheHandler(dir);
    const second = createFileCacheHandler(dir);

    await first.set("islands", entry("ten islands", ["user:1"]));
    await second.refreshTags();
    const hit = await second.get("islands", []);

    expect(hit).toBeDefined();
    expect(await read(hit!.value)).toBe("ten islands");
  });

  it("misses on both instances once either expires a tag", async () => {
    const first = createFileCacheHandler(dir);
    const second = createFileCacheHandler(dir);

    await first.set("islands", entry("ten islands", ["user:1"]));
    await first.set("other", entry("someone else", ["user:2"]));
    await delay(5);
    await second.updateTags(["user:1"]);

    await first.refreshTags();
    expect(await first.get("islands", [])).toBeUndefined();
    expect(await second.get("islands", [])).toBeUndefined();
    expect(await first.get("other", [])).toBeDefined();
    expect(await first.getExpiration(["user:1"])).toBeGreaterThan(0);
  });

  it("serves a stale-tagged entry for revalidation", async () => {
    const handler = createFileCacheHandler(dir);

    await handler.set("islands", entry("ten islands", ["user:1"]));
    await delay(5);
    await handler.updateTags(["user:1"], { expire: 60 });

    expect((await handler.get("islands", []))?.revalidate).toBe(-1);
  });
});
