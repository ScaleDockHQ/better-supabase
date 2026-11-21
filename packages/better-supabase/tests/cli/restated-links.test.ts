import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { runCodemod } from "../../src/cli/commands/codemod.ts";
import { probeRestated } from "../../src/cli/restated-probe.ts";
import { resolveConfig } from "../../src/config/index.ts";

const SCHEMA = `create table public.organization_tags (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  name text not null,
  kind text not null default 'general',
  rank text collate "C" not null default 'V',
  created_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  title text not null
);

create table public.task_tags (
  task_id uuid not null references public.tasks (id) on delete cascade,
  tag_id uuid not null references public.organization_tags (id) on delete cascade,
  primary key (task_id, tag_id)
);
`;

const LINKS = { table: "public.task_tags", subject: "task_id", tag: "tag_id" };

const CONFIG_TEXT = `export default {
  blocks: [
    {
      block: "tags",
      tables: { tags: "public.organization_tags", taggings: null },
      on: {
        task: {
          table: "public.tasks",
          links: { table: "public.task_tags", subject: "task_id", tag: "tag_id" },
        },
      },
    },
  ],
};
`;

function project(links: object) {
  const root = mkdtempSync(join(tmpdir(), "bsb-links-"));

  mkdirSync(join(root, "supabase", "schemas"), { recursive: true });
  writeFileSync(join(root, "supabase", "schemas", "app.sql"), SCHEMA);

  const file = join(root, "better-supabase.config.ts");

  writeFileSync(file, CONFIG_TEXT);

  return {
    file,
    config: resolveConfig(
      {
        blocks: {
          tags: {
            tables: { tags: "public.organization_tags", taggings: null },
            on: { task: { table: "public.tasks", links } },
          },
        },
      },
      root,
    ),
  };
}

describe("links the foreign keys give", () => {
  it("is found by the probe as restated", async () => {
    const { config } = project(LINKS);

    expect((await probeRestated(config)).map((entry) => entry.path)).toContain(
      "blocks.tags.on.task.links",
    );
  });

  it("is kept when it names a different column", async () => {
    const { config } = project({ ...LINKS, tag: "other_id" });

    expect(
      (await probeRestated(config).catch(() => [])).map((entry) => entry.path),
    ).not.toContain("blocks.tags.on.task.links");
  });

  it("is removed from the config file by codemod config --prune", async () => {
    const { config, file } = project(LINKS);

    await runCodemod(config, { _: ["config"], prune: true }, undefined, file);

    const text = readFileSync(file, "utf-8");

    expect(text).not.toContain("links");
    expect(text).toContain('table: "public.tasks"');
  });
});
