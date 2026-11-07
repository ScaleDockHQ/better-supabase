import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { installMemo } from "../../../src/cli/cache/memo-backend.ts";
import { createDiskParseStore } from "../../../src/cli/cache/parse-store.ts";
import { setCacheEnabled } from "../../../src/cli/cache/store.ts";
import {
  buildModel,
  createParseCache,
  parseDeclared,
  setParseStore,
} from "../../../src/sql/pipeline/model.ts";

let folder = "";

beforeEach(async () => {
  folder = await mkdtemp(join(tmpdir(), "bsb-parse-store-"));
});

afterEach(async () => {
  setParseStore(undefined);
  await rm(folder, { recursive: true, force: true });
});

const text = "create table public.notes (id uuid primary key, body text);\n";
const file = (): string => join(folder, "parse", "files.json");

describe("the disk parse store", () => {
  it("serves a text an earlier run parsed, with the same result", () => {
    const first = createDiskParseStore(folder, "s1");
    const cache = createParseCache(first);
    const parsed = cache.get(text);

    expect(cache.stats).toEqual({ parsed: 1, hits: 0 });
    expect(first.flush()).toBe(true);

    const second = createParseCache(createDiskParseStore(folder, "s1"));

    expect(second.get(text)).toEqual(parseDeclared(text));
    expect(second.get(text)).toEqual(parsed);
    expect(second.stats).toEqual({ parsed: 0, hits: 2 });
  });

  it("parses again when the text changes, and only that text", () => {
    const first = createDiskParseStore(folder, "s1");
    const cache = createParseCache(first);
    cache.get(text);
    cache.get("create table public.a (id int);");
    first.flush();

    const next = createParseCache(createDiskParseStore(folder, "s1"));
    next.get(text);
    next.get("create table public.a (id int, b int);");

    expect(next.stats).toEqual({ parsed: 1, hits: 1 });
  });

  it("writes nothing when the run added nothing", () => {
    const first = createDiskParseStore(folder, "s1");
    createParseCache(first).get(text);
    first.flush();

    const again = createDiskParseStore(folder, "s1");
    createParseCache(again).get(text);

    expect(again.flush()).toBe(false);
  });

  it("drops a file from another release and one that can't be read", async () => {
    const first = createDiskParseStore(folder, "s1");
    createParseCache(first).get(text);
    first.flush();

    const other = createParseCache(createDiskParseStore(folder, "s2"));
    other.get(text);
    expect(other.stats.parsed).toBe(1);

    await writeFile(file(), "{ not json");
    const damaged = createParseCache(createDiskParseStore(folder, "s1"));
    damaged.get(text);
    expect(damaged.stats.parsed).toBe(1);
  });

  it("parses again when a stored entry has the wrong shape", async () => {
    await mkdir(join(folder, "parse"), { recursive: true });

    const key = (() => {
      const probe = createDiskParseStore(folder, "s1");
      createParseCache(probe).get(text);
      probe.flush();

      return Object.keys(
        JSON.parse(readFileSync(file(), "utf-8")).entries as object,
      )[0]!;
    })();

    await writeFile(
      file(),
      JSON.stringify({ salt: "s1", entries: { [key]: { objects: 1 } } }),
    );

    const cache = createParseCache(createDiskParseStore(folder, "s1"));
    expect(cache.get(text)).toEqual(parseDeclared(text));
    expect(cache.stats.parsed).toBe(1);
  });

  it("keeps the file bounded, dropping the entries a run did not use", async () => {
    const first = createDiskParseStore(folder, "s1");
    const cache = createParseCache(first);

    for (let n = 0; n < 4100; n += 1) {
      cache.get(`create table public.t${String(n)} (id int);`);
    }

    first.flush();

    const stored = JSON.parse(await readFile(file(), "utf-8")) as {
      entries: Record<string, unknown>;
    };

    expect(Object.keys(stored.entries)).toHaveLength(4096);

    // The newest are kept.
    const next = createParseCache(createDiskParseStore(folder, "s1"));
    next.get("create table public.t4099 (id int);");
    next.get("create table public.t0 (id int);");
    expect(next.stats).toEqual({ parsed: 1, hits: 1 });
  });

  it("is what buildModel reads by default once it is installed", () => {
    const first = createDiskParseStore(folder, "s1");
    setParseStore(first);
    buildModel([{ path: "a.sql", text }]);
    first.flush();

    const second = createDiskParseStore(folder, "s1");
    setParseStore(second);
    const model = buildModel([{ path: "a.sql", text }]);

    expect(model.objects.has("table:public.notes")).toBe(true);
    expect(second.flush()).toBe(false);
  });

  it("is installed by the CLI unless the run has no cache", async () => {
    setCacheEnabled(true);
    await installMemo(folder);
    createParseCache().get(text);
    expect(createParseCache().stats).toEqual({ parsed: 0, hits: 0 });
    expect(createParseCache().get(text)).toEqual(parseDeclared(text));
    expect(createParseCache().stats.hits).toBe(0);

    const again = createParseCache();
    again.get(text);
    expect(again.stats).toEqual({ parsed: 0, hits: 1 });

    setCacheEnabled(false);
    await installMemo(folder);
    const bare = createParseCache();
    bare.get(text);
    expect(bare.stats).toEqual({ parsed: 1, hits: 0 });
    setCacheEnabled(true);
  });
});
