import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import {
  schemaTagComments,
  withSchemaTags,
} from "../../src/cli/schema-tags.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { tableTagComments } from "../../src/sql/index.ts";

let dir: string | undefined;

afterEach(async () => {
  if (dir !== undefined) {
    await rm(dir, { recursive: true, force: true });
    dir = undefined;
  }
});

describe("tableTagComments", () => {
  it("returns only tagged comments, qualified or not", () => {
    expect(
      tableTagComments(
        [
          "comment on table public.a is 'Plain.';",
          "comment on table \"b\" is 'It''s. @bsb realtime';",
          "comment on table app.c is '@bsb subject';",
        ].join("\n"),
      ),
    ).toEqual([
      { schema: "public", name: "b", comment: "It's. @bsb realtime" },
      { schema: "app", name: "c", comment: "@bsb subject" },
    ]);
  });
});

describe("withSchemaTags", () => {
  it("turns the schema files' tags into config", async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-tags-"));
    await mkdir(join(dir, "supabase", "schemas", "public", "tables"), {
      recursive: true,
    });
    await writeFile(join(dir, "supabase", "config.toml"), "");
    await writeFile(
      join(dir, "supabase", "schemas", "public", "tables", "projects.sql"),
      "create table public.projects (id uuid primary key, name text);\ncomment on table public.projects is '@bsb subject type=project title=name; realtime';\n",
    );

    const config = resolveConfig({ blocks: {} }, dir);
    const next = await withSchemaTags(config);

    expect(await schemaTagComments(config)).toHaveLength(1);
    expect(next.subjects["project"]).toEqual({
      table: "projects",
      title: "name",
    });
    expect(next.realtime.tables).toContain("projects");
  });

  it("returns the config itself when the project has no schema files", async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-tags-"));
    const config = resolveConfig({ blocks: {} }, dir);

    expect(await withSchemaTags(config)).toBe(config);
  });
});
