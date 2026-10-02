import type * as Crypto from "node:crypto";

import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Queryable } from "../../../src/cli/introspect/source.ts";

import {
  type Lint,
  managementAdvisors,
  splinterAdvisors,
} from "../../../src/cli/doctor/advisors.ts";
import { fakeFetch } from "../../fixtures/fake-fetch.ts";

const COMMIT = "e74a9e36cb12258cb67d1464bc1cb196e9cd8446";
const URL = `https://raw.githubusercontent.com/supabase/splinter/${COMMIT}/splinter.sql`;
const SQL = "select 'lint' as name;";

// The real splinter.sql is not vendored (AGENTS.md invariant 13), so the
// fixture SQL is made to hash to the pinned SPLINTER_SHA256.
// vi.hoisted runs before the static imports, so it loads fs itself.
const PINNED = vi.hoisted(async () => {
  const { readFile: read } = await import("node:fs/promises");
  const source = await read(
    new globalThis.URL("../../../src/cli/doctor/advisors.ts", import.meta.url),
    "utf8",
  );
  return /SPLINTER_SHA256 =\s*"([0-9a-f]{64})"/.exec(source)![1]!;
});

vi.mock("node:crypto", async (importOriginal) => {
  const crypto = await importOriginal<typeof Crypto>();
  const pinned = await PINNED;
  return {
    ...crypto,
    createHash: (algorithm: string) => {
      const hash = crypto.createHash(algorithm);
      let input = "";
      return {
        update(data: string) {
          input += data;
          hash.update(data);
          return this;
        },
        digest: (encoding: "hex") =>
          input === "select 'lint' as name;" ? pinned : hash.digest(encoding),
      };
    },
  };
});

const lint = (name: string, categories: string[]): Lint => ({
  name,
  title: name,
  level: "WARN",
  facing: "EXTERNAL",
  categories,
  description: "",
  detail: "",
  remediation: "",
  metadata: null,
  cache_key: `${name}_key`,
});

const recording = (result: unknown): Queryable & { texts: string[] } => {
  const texts: string[] = [];
  return {
    texts,
    // SAFETY: pg returns this shape (or one per statement) for the splinter query.
    query: (text: string) => {
      texts.push(text);
      return Promise.resolve(result as { rows: [] });
    },
  };
};

describe("splinterAdvisors", () => {
  let cacheDir: string;
  const cached = () => join(cacheDir, `splinter-${COMMIT}.sql`);

  beforeEach(async () => {
    cacheDir = join(
      await mkdtemp(join(tmpdir(), "better-supabase-splinter-")),
      "cache",
    );
  });

  afterEach(async () => {
    await rm(join(cacheDir, ".."), { recursive: true, force: true });
  });

  it("refuses a download that does not match the pinned hash", async () => {
    const download = fakeFetch(() => ({ text: "drop table users;" }));
    const advisors = splinterAdvisors(recording({ rows: [] }), "local", {
      cacheDir,
      fetch: download.fetch,
    });
    expect(advisors.describe).toBe("local (splinter e74a9e3)");
    await expect(advisors.lints("security")).rejects.toThrow(
      `splinter.sql from ${URL} does not match the pinned hash; refusing to run it.`,
    );
    expect(download.calls.map((call) => call.url)).toEqual([URL]);
    expect(existsSync(cached())).toBe(false);
  });

  it("reports a failed download with the status", async () => {
    const advisors = splinterAdvisors(recording({ rows: [] }), "local", {
      cacheDir,
      fetch: fakeFetch(() => ({ status: 503 })).fetch,
    });
    await expect(advisors.lints("security")).rejects.toThrow(
      `Downloading splinter.sql failed (503) from ${URL}`,
    );
  });

  it("caches a verified download and runs it read-only, once, per category", async () => {
    const download = fakeFetch(() => ({ text: SQL }));
    const db = recording([
      { rows: [], fields: [] },
      {
        rows: [
          lint("rls_disabled_in_public", ["SECURITY"]),
          lint("unindexed_foreign_keys", ["PERFORMANCE"]),
          { name: "broken" },
          null,
        ],
        fields: [{ name: "name" }, { name: "cache_key" }],
      },
      { rows: [], fields: [] },
    ]);
    const advisors = splinterAdvisors(db, "local", {
      cacheDir,
      fetch: download.fetch,
    });
    expect((await advisors.lints("security")).map((l) => l.name)).toEqual([
      "rls_disabled_in_public",
    ]);
    expect((await advisors.lints("performance")).map((l) => l.name)).toEqual([
      "unindexed_foreign_keys",
    ]);
    expect(db.texts).toEqual([`begin read only;\n${SQL}\n;\nrollback;`]);
    expect(download.calls).toHaveLength(1);
    expect(await readFile(cached(), "utf8")).toBe(SQL);

    const offline = fakeFetch(() => {
      throw new Error("offline");
    });
    const again = splinterAdvisors(
      recording({ rows: [lint("a", ["SECURITY"])] }),
      "local",
      { cacheDir, fetch: offline.fetch },
    );
    expect((await again.lints("security")).map((l) => l.name)).toEqual(["a"]);
    expect(offline.calls).toEqual([]);
  });

  it("downloads again when the cached file was changed", async () => {
    const first = splinterAdvisors(recording({ rows: [] }), "local", {
      cacheDir,
      fetch: fakeFetch(() => ({ text: SQL })).fetch,
    });
    await first.lints("security");
    await writeFile(cached(), "drop table users;");
    const download = fakeFetch(() => ({ text: SQL }));
    const db = recording([{ rows: [lint("b", ["SECURITY"])] }]);
    const advisors = splinterAdvisors(db, "local", {
      cacheDir,
      fetch: download.fetch,
    });
    expect((await advisors.lints("security")).map((l) => l.name)).toEqual([
      "b",
    ]);
    expect(download.calls).toHaveLength(1);
    expect(db.texts[0]).toContain(SQL);
    expect(await readFile(cached(), "utf8")).toBe(SQL);
  });

  it("returns nothing when the result has no rows", async () => {
    const advisors = splinterAdvisors(recording([]), "local", {
      cacheDir,
      fetch: fakeFetch(() => ({ text: SQL })).fetch,
    });
    expect(await advisors.lints("security")).toEqual([]);
  });
});

describe("managementAdvisors", () => {
  it("reads one category per call with the access token", async () => {
    const api = fakeFetch((call) => ({
      body: {
        lints: [
          lint(call.url.endsWith("/security") ? "s" : "p", ["SECURITY"]),
          { name: 1 },
        ],
      },
    }));
    const advisors = managementAdvisors({
      projectRef: "abc",
      accessToken: "sbp_x",
      apiUrl: "http://api.test/",
      fetch: api.fetch,
    });
    expect(advisors.describe).toBe("project abc advisors (Management API)");
    expect((await advisors.lints("security")).map((l) => l.name)).toEqual([
      "s",
    ]);
    expect((await advisors.lints("performance")).map((l) => l.name)).toEqual([
      "p",
    ]);
    expect(api.calls.map((call) => call.url)).toEqual([
      "http://api.test/v1/projects/abc/advisors/security",
      "http://api.test/v1/projects/abc/advisors/performance",
    ]);
    expect(api.calls[0]!.headers.get("authorization")).toBe("Bearer sbp_x");
  });

  it("reports API errors and bodies without lints", async () => {
    const failing = managementAdvisors({
      projectRef: "abc",
      accessToken: "t",
      fetch: fakeFetch(() => ({ status: 403, text: "forbidden" })).fetch,
    });
    await expect(failing.lints("security")).rejects.toThrow(
      "Management API security advisors failed (403): forbidden",
    );
    const empty = managementAdvisors({
      projectRef: "abc",
      accessToken: "t",
      fetch: fakeFetch(() => ({ body: {} })).fetch,
    });
    await expect(empty.lints("performance")).rejects.toThrow(
      'Management API performance advisors returned no "lints".',
    );
  });
});
