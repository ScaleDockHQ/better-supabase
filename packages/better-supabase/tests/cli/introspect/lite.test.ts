import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { CliError } from "../../../src/cli/errors.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { liteDriverOf, liteSource } from "../../../src/cli/introspect/lite.ts";
import { readSupabaseToml } from "../../../src/cli/supabase-toml.ts";

const dirs: string[] = [];

async function project(files: Record<string, string>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bs-lite-"));
  dirs.push(root);
  await writeFile(join(root, ".git"), "");
  for (const [path, text] of Object.entries(files)) {
    await mkdir(join(root, path, ".."), { recursive: true });
    await writeFile(join(root, path), text);
  }
  return root;
}

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

describe("liteDriverOf", () => {
  it("reads [db] driver and rejects unknown drivers", async () => {
    const lite = await project({
      "supabase/config.toml": '[db]\ndriver = "pglite"\n',
    });
    expect(liteDriverOf(await readSupabaseToml(lite))).toBe("pglite");
    const plain = await project({
      "supabase/config.toml": "[db]\nport = 54322\n",
    });
    expect(liteDriverOf(await readSupabaseToml(plain))).toBeUndefined();
    const wrong = await project({
      "supabase/config.toml": '[db]\ndriver = "mysql"\n',
    });
    const toml = await readSupabaseToml(wrong);
    expect(() => liteDriverOf(toml)).toThrow(CliError);
  });
});

/** Replaying into PGlite takes seconds, more under coverage. */
describe("liteSource", { timeout: 30_000 }, () => {
  it("replays migrations and declarative schemas into PGlite for introspection", async () => {
    const root = await project({
      "supabase/config.toml": '[db]\ndriver = "sqlite-postgres"\n',
      "supabase/migrations/20260101000000_notes.sql":
        "create table public.notes (id uuid primary key default gen_random_uuid(), body text not null, owner uuid);\nalter table public.notes enable row level security;",
      "supabase/migrations/20260102000000_tags.sql":
        "alter table public.notes add column tags text[];",
      "supabase/schemas/count.sql":
        "create function public.note_count() returns bigint language sql as $$ select count(*) from public.notes $$;",
    });
    const toml = await readSupabaseToml(root);
    const source = await liteSource(root, toml, "sqlite-postgres");
    expect(source.replay).toMatch(/replayed into an in-memory PGlite/);
    try {
      const snapshot = await introspect(source.queryable, ["public"]);
      const notes = snapshot.generator.tables.find((t) => t.name === "notes");
      expect(notes?.rls_enabled).toBe(true);
      expect(
        snapshot.generator.columns
          .filter((column) => column.table === "notes")
          .map((column) => column.name)
          .sort(),
      ).toEqual(["body", "id", "owner", "tags"]);
      expect(snapshot.generator.functions.map((fn) => fn.name)).toContain(
        "note_count",
      );
    } finally {
      await source.close();
    }
  });

  it("explains a schema that fails to replay", async () => {
    const root = await project({
      "supabase/config.toml": '[db]\ndriver = "pglite"\n',
      "supabase/migrations/1_bad.sql": "create table broken (",
    });
    await expect(
      liteSource(root, await readSupabaseToml(root), "pglite"),
    ).rejects.toThrow(/Replaying the Supabase Lite schema/);
  });

  it("needs a url for the postgres driver and refuses the bare sqlite driver", async () => {
    const root = await project({
      "supabase/config.toml": '[db]\ndriver = "postgres"\n',
    });
    const toml = await readSupabaseToml(root);
    await expect(liteSource(root, toml, "postgres")).rejects.toThrow(
      /\[db\] url/,
    );
    await expect(liteSource(root, toml, "sqlite")).rejects.toThrow(
      /sqlite-postgres/,
    );
    await expect(liteSource(root, undefined, "postgres")).rejects.toThrow(
      /\[db\] url/,
    );
  });

  it("reads the postgres driver's [db] url", async () => {
    const root = await project({
      "supabase/config.toml":
        '[db]\ndriver = "postgres"\nurl = "postgresql://u:p@db/x"\n',
    });
    const urls: string[] = [];
    const source = await liteSource(
      root,
      await readSupabaseToml(root),
      "postgres",
      (url) => {
        urls.push(url);
        return Promise.resolve({
          client: { query: <R>() => Promise.resolve({ rows: [] as R[] }) },
          pooled: true,
          close: () => Promise.resolve(),
          describe: "postgresql://u:***@db/x",
        });
      },
    );
    expect(urls).toEqual(["postgresql://u:p@db/x"]);
    expect(source.describe).toBe("postgresql://u:***@db/x");
  });

  it("opens an empty PGlite when the project has no schema files", async () => {
    const root = await project({});
    const source = await liteSource(root, undefined, "pglite");
    try {
      const snapshot = await introspect(source.queryable, ["public"]);
      expect(snapshot.generator.tables).toEqual([]);
    } finally {
      await source.close();
    }
  });
});
