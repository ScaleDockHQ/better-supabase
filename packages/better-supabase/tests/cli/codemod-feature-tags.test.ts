import { describe, expect, it } from "vitest";

import type { CodemodProject } from "../../src/cli/codemod.ts";
import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import { broadcastTriggerReview } from "../../src/cli/codemod-feature-tags.ts";
import { tableTagFiles } from "../../src/cli/codemod-table-tags.ts";
import { primeSchemaFacts } from "../../src/cli/sql-facts.ts";
import { resolveConfig } from "../../src/config/index.ts";

const CONFIG = `export default defineConfig({
  recordTypes: {
    task: { table: "tasks", title: "name", template: "is_template" },
    plan: { table: "plans", team: { actions: ["write"] } },
  },
  realtime: {
    tables: ["notes", "tasks", "pings"],
    global: ["pings", "notes"],
    users: { tasks: "owner_id" },
  },
  vectorSearch: {
    docs: { column: "embedding", distance: "l2" },
    pages: { column: "embedding", distance: "cosine", dimensions: 3 },
  },
});
`;

// SAFETY: the test config omits block fields the types require
const input = {
  recordTypes: {
    task: { table: "tasks", title: "name", template: "is_template" },
    plan: { table: "plans", team: { actions: ["write"] } },
  },
  realtime: {
    tables: ["notes", "tasks", "pings"],
    global: ["pings", "notes"],
    users: { tasks: "owner_id" },
  },
  vectorSearch: { docs: { column: "embedding", distance: "l2" } },
} as unknown as BetterSupabaseConfig;

const sql = (name: string): CodemodProject["sql"][number] => ({
  path: `/project/supabase/schemas/${name}.sql`,
  text: `create table public.${name} (id uuid primary key);\n`,
});

const run = async (): Promise<ReturnType<typeof tableTagFiles>> => {
  const target: CodemodProject = {
    config: resolveConfig(input, "/project"),
    sql: ["tasks", "plans", "notes", "pings", "docs"].map(sql),
    configFile: "/project/better-supabase.config.ts",
    configText: CONFIG,
  };

  await primeSchemaFacts(target.sql, "/project");

  return tableTagFiles(target);
};

describe("record type, realtime and vector search moves", () => {
  it("writes the tags and drops the entries from the config", async () => {
    const { files, review } = await run();

    const text = (path: string): string =>
      files.find((file) => file.path.endsWith(path))?.contents ?? "";

    expect(text("tasks.sql")).toContain(
      "subject type=task title=name template=is_template; realtime user=owner_id",
    );
    expect(text("notes.sql")).toContain("@bsb realtime global");
    expect(text("pings.sql")).toContain("@bsb realtime global");
    expect(text("docs.sql")).toContain(
      "@bsb vector-search column=embedding distance=l2",
    );

    const config = text("better-supabase.config.ts");

    expect(config).not.toContain("template:");
    expect(config).not.toMatch(/tables: \["/u);
    expect(config).not.toContain("owner_id");
    expect(config).not.toContain("docs:");
    expect(config).toContain("plan:");
    expect(review.map((line) => line.message).join("\n")).toContain(
      "recordTypes.plan stays in the config",
    );
  });

  it("leaves the global list empty after both global tables move", async () => {
    const { files } = await run();

    const config =
      files.find((file) => file.path.endsWith("config.ts"))?.contents ?? "";

    expect(config).toMatch(/global: \[\s*\]/u);
  });
});

describe("broadcastTriggerReview", () => {
  it("names a hand-written broadcast_topic trigger and skips migrations", () => {
    const text = `create trigger quotes_broadcast
  after insert or update on public.quotes
  for each row execute function better_supabase.broadcast_topic('org:{organization_id}:quotes', 'quote.changed');
create trigger other after insert on public.t for each row execute function public.f();`;

    const lines = broadcastTriggerReview([
      { path: "/p/supabase/schemas/quotes.sql", text },
      { path: "/p/supabase/migrations/1_quotes.sql", text },
    ]);

    expect(lines).toHaveLength(1);
    expect(lines[0]?.message).toContain(
      "trigger quotes_broadcast on public.quotes",
    );
  });
});
