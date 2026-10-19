import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { runApply } from "../../../src/cli/commands/apply.ts";
import { runBlocks } from "../../../src/cli/commands/blocks.ts";
import { runPreset } from "../../../src/cli/commands/preset.ts";
import { run } from "../../../src/cli/core/run.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import {
  type CreateDesign,
  encodeDesign,
  encodePreset,
  namedPreset,
} from "../../../src/preset/index.ts";
import { usageError } from "../fixtures/usage.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-presets-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

async function files(entries: Record<string, string>): Promise<void> {
  for (const [path, contents] of Object.entries(entries)) {
    await mkdir(dirname(join(dir, path)), { recursive: true });
    await writeFile(join(dir, path), contents);
  }
}

const json = (value: unknown): string => `${JSON.stringify(value, null, 2)}\n`;

const now = () => new Date("2026-10-15T12:00:00Z");

const design: CreateDesign = {
  appTables: {
    notes: { scope: "user", columns: { body: { type: "text" } } },
  },
  extraColumns: { profiles: { nickname: "text" } },
  positions: { "public.notes": [120, 40] },
};

/** The `/create` URL for the minimal preset with `value` as its design. */
async function designUrl(value: CreateDesign = design): Promise<string> {
  return `https://bettersupabase.com/create?preset=${encodePreset(namedPreset("minimal"))}&design=${await encodeDesign(value)}`;
}

const APP_TABLES_FILE = "supabase/schemas/900_better_supabase_app_tables.sql";

describe("preset decode", () => {
  it("prints a named preset, a code and a /create URL", () => {
    const config = resolveConfig({}, dir);
    const named = runPreset(config, { _: ["decode", "minimal"] });
    expect(named.code).toBe(0);
    expect(named.output).toContain(
      `Code: ${encodePreset(namedPreset("minimal"))}`,
    );
    expect(named.output).toContain("  profiles");
    const code = encodePreset({ blocks: ["comments"], casing: "camel" });

    const decoded = runPreset(config, {
      _: ["decode", `https://bettersupabase.com/create?preset=${code}`],
    });

    expect(decoded.output).toContain("  casing        camel");
    expect(decoded.output).toContain(
      "  tenant (required by access and comments)",
    );
    expect(decoded.data).toMatchObject({ code, derived: [] });
  });

  it("exits 1 on what can't install, and 2 on what isn't a preset", async () => {
    const config = resolveConfig({}, dir);

    const conflict = runPreset(config, {
      _: ["decode", encodePreset({ blocks: ["organizations"], scope: "user" })],
    });

    expect(conflict.code).toBe(1);
    expect(conflict.output).toContain(
      'Can\'t install:\n  organizations: it needs tenants, and scope "user" has none',
    );
    await usageError(() => runPreset(config, { _: ["decode", "startup"] }));
    await usageError(() => runPreset(config, { _: ["decode"] }));
    await usageError(() => runPreset(config, { _: [] }));
    expect(
      await usageError(() => runPreset(config, { _: ["nope"] })),
    ).toContain('Unknown preset action "nope"');
  });
});

describe("preset info", () => {
  it("shows how the config differs from its preset", () => {
    const config = resolveConfig(
      {
        preset: "minimal",
        casing: "camel",
        blocks: { tags: {}, profiles: { mode: "custom" } },
      },
      dir,
    );

    const info = runPreset(config, { _: ["info"] });
    expect(info.code).toBe(0);
    expect(info.output).toContain("Preset: minimal");
    expect(info.output).toContain("  + tags");
    expect(info.output).toContain("  ~ casing is camel, the preset sets snake");
    expect(info.output).toContain("  ~ profiles sets mode");
    expect(info.data).toMatchObject({ name: "minimal", added: ["tags"] });
  });

  it("says when the config adds nothing, or names no preset", () => {
    expect(
      runPreset(resolveConfig({ preset: "minimal" }, dir), { _: ["info"] })
        .output,
    ).toContain("The config adds nothing to the preset.");
    expect(runPreset(resolveConfig({}, dir), { _: ["info"] }).output).toContain(
      "The config names no preset.",
    );
  });
});

describe("blocks", () => {
  it("lists every block by category, or one category", async () => {
    const all = runBlocks({ _: ["list"] });
    expect(all.output).toContain("identity:\n");
    expect(all.output).toContain("  comments");
    const crm = runBlocks({ _: ["list"], category: "crm" });
    expect(crm.output).toMatch(/^crm:\n/);
    expect(crm.output).not.toContain("identity:");
    await usageError(() => runBlocks({ _: ["list"], category: "nope" }));
  });

  it("shows one block with its install command and glue", async () => {
    const view = runBlocks({ _: ["view", "outbox"] });
    expect(view.code).toBe(0);
    expect(view.output).toContain("Install: better-supabase add outbox");
    expect(view.output).toContain("@better-supabase/outbox-relay-next");
    expect(view.output).toContain(
      "More: https://bettersupabase.com/blocks/outbox",
    );
    expect(runBlocks({ _: ["view", "tenant"] }).output).toContain(
      "Requires:   updated-at",
    );
    await usageError(() => runBlocks({ _: ["view"] }));
    expect(
      await usageError(() => runBlocks({ _: ["view", "nope"] })),
    ).toContain("better-supabase blocks search nope");
  });

  it("searches names, titles and descriptions", async () => {
    expect(runBlocks({ _: ["search", "invoice"] }).output).toContain(
      "  invoices",
    );
    expect(runBlocks({ _: ["search", "zzzz"] }).output).toContain(
      'No block matches "zzzz"',
    );
    await usageError(() => runBlocks({ _: ["search"] }));
    await usageError(() => runBlocks({ _: [] }));
    await usageError(() => runBlocks({ _: ["nope"] }));
  });
});

describe("apply", () => {
  it("sets preset in the config, shows the diff and writes the modules", async () => {
    await files({
      "better-supabase.config.json": json({ blocks: { tags: {} } }),
    });
    const result = await run(["apply", "--preset", "minimal", "--cwd", dir]);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain('+  "preset": "minimal"');
    expect(
      JSON.parse(
        await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
      ),
    ).toEqual({ blocks: { tags: {} }, preset: "minimal" });
    expect(
      existsSync(
        join(dir, "supabase/schemas/900_better_supabase_22_profiles.sql"),
      ),
    ).toBe(true);
    expect(
      (await run(["apply", "--preset", "minimal", "--cwd", dir])).stdout,
    ).toContain("already holds the preset");
  });

  it("writes nothing with --dry-run, and lists blocks with --only blocks", async () => {
    await files({ "better-supabase.config.json": json({}) });

    const dry = await run([
      "apply",
      "--preset",
      "minimal",
      "--dry-run",
      "--cwd",
      dir,
    ]);

    expect(dry.stdout).toContain("Dry run: nothing written.");
    expect(
      await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
    ).toBe(json({}));

    const blocks = await run([
      "apply",
      "--preset",
      encodePreset({ blocks: ["comments"] }),
      "--only",
      "blocks",
      "--cwd",
      dir,
    ]);

    expect(blocks.code).toBe(0);
    expect(
      JSON.parse(
        await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
      ),
    ).toEqual({
      blocks: { "updated-at": {}, tenant: {}, access: {}, comments: {} },
    });
  });

  it("takes only the conventions with --only conventions", async () => {
    await files({
      "better-supabase.config.ts":
        "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  casing: 'snake',\n});\n",
    });
    const preset = { ...namedPreset("saas"), casing: "camel" as const };

    const result = await runApply(
      resolveConfig({}, dir),
      { preset: encodePreset(preset), only: "conventions" },
      {
        configFile: join(dir, "better-supabase.config.ts"),
        now,
        reload: () => Promise.resolve(resolveConfig({ casing: "camel" }, dir)),
      },
    );

    expect(result.code).toBe(0);
    const code = encodePreset({ ...preset, blocks: [] });
    expect(
      await readFile(join(dir, "better-supabase.config.ts"), "utf-8"),
    ).toContain(`  casing: 'snake',\n  preset: '${code}',\n`);
  });

  it("refuses what it can't apply", async () => {
    const config = resolveConfig({}, dir);
    const deps = { now, configFile: join(dir, "better-supabase.config.ts") };
    await usageError(() => runApply(config, {}, deps));
    expect(
      await usageError(() =>
        runApply(config, { preset: "saas", only: "all" }, deps),
      ),
    ).toBe('--only must be "blocks" or "conventions"');
    await expect(
      runApply(config, { preset: "saas" }, { now }),
    ).rejects.toMatchObject({
      code: "config_not_found",
      message: expect.stringContaining("better-supabase init --preset saas"),
    });
    await usageError(() => runApply(config, { preset: "startup" }, deps));
    expect(
      await usageError(() =>
        runApply(
          config,
          {
            preset: encodePreset({ blocks: ["organizations"], scope: "none" }),
          },
          deps,
        ),
      ),
    ).toContain("The preset can't install: organizations");
    await files({ "better-supabase.config.ts": "export default config;\n" });
    expect((await runApply(config, { preset: "saas" }, deps)).error).toContain(
      "wasn't changed: it doesn't pass an object literal to defineConfig()",
    );
  });
});

describe("apply with a design", () => {
  it("merges the design's app tables and extra columns into the config", async () => {
    await files({
      "better-supabase.config.json": json({
        blocks: { profiles: { options: { extraColumns: { bio: "text" } } } },
        appTables: {
          links: { scope: "user", columns: { url: { type: "text" } } },
        },
      }),
    });

    const result = await run([
      "apply",
      "--preset",
      await designUrl(),
      "--cwd",
      dir,
    ]);

    expect(result.stderr).toBe("");
    expect(result.code).toBe(0);
    expect(
      JSON.parse(
        await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
      ),
    ).toEqual({
      blocks: {
        profiles: {
          options: { extraColumns: { bio: "text", nickname: "text" } },
        },
      },
      appTables: {
        links: { scope: "user", columns: { url: { type: "text" } } },
        notes: { scope: "user", columns: { body: { type: "text" } } },
      },
      preset: encodePreset(namedPreset("minimal")),
    });
    expect(await readFile(join(dir, APP_TABLES_FILE), "utf-8")).toContain(
      '"public"."notes"',
    );
  });

  it("writes the design into a TypeScript config", async () => {
    await files({
      "better-supabase.config.ts":
        "import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  casing: 'snake',\n});\n",
    });

    const result = await runApply(
      resolveConfig({}, dir),
      { preset: await designUrl(), "dry-run": true },
      { configFile: join(dir, "better-supabase.config.ts"), now },
    );

    expect(result.code).toBe(0);
    expect(result.output).toContain("+  appTables: {");
    expect(result.output).toContain("+    notes: {");
    expect(result.output).toContain("+          nickname: 'text',");
  });

  it("refuses a damaged design and an extra column without its block", async () => {
    await files({ "better-supabase.config.json": json({}) });
    const url = await designUrl();

    const damaged = await run([
      "apply",
      "--preset",
      `${url.slice(0, -4)}!!!!`,
      "--cwd",
      dir,
    ]);

    expect(damaged.code).toBe(2);

    const stray = await run([
      "apply",
      "--preset",
      await designUrl({ extraColumns: { organizations: { tier: "text" } } }),
      "--cwd",
      dir,
    ]);

    expect(stray.code).toBe(2);
    expect(stray.stderr).toContain("design.extraColumns.organizations");
    expect(
      await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
    ).toBe(json({}));
  });

  it("needs --allow-breaking to retype or drop a column of an app table", async () => {
    const before = json({
      appTables: {
        notes: {
          scope: "user",
          columns: { body: { type: "jsonb" }, pinned: { type: "boolean" } },
        },
      },
    });

    await files({ "better-supabase.config.json": before });
    const url = await designUrl({ appTables: design.appTables ?? {} });

    const refused = await run(["apply", "--preset", url, "--cwd", dir]);

    expect(refused.code).toBe(1);
    expect(refused.stdout).toContain("Breaking changes to app tables:");
    expect(refused.stdout).toContain("Changes notes.body from jsonb to text.");
    expect(refused.stdout).toContain("Drops notes.pinned and its values.");
    expect(refused.stdout).toContain("1. Add a text column next to body.");
    expect(refused.stderr).toContain("2 breaking changes");
    expect(refused.stderr).toContain("--allow-breaking");
    expect(
      await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
    ).toBe(before);

    const dry = await run([
      "apply",
      "--preset",
      url,
      "--dry-run",
      "--cwd",
      dir,
    ]);

    expect(dry.code).toBe(0);
    expect(dry.stdout).toContain("Breaking changes to app tables:");

    const allowed = await run([
      "apply",
      "--preset",
      url,
      "--allow-breaking",
      "--cwd",
      dir,
    ]);

    expect(allowed.code).toBe(0);
    expect(
      JSON.parse(
        await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
      ),
    ).toMatchObject({
      appTables: {
        notes: { scope: "user", columns: { body: { type: "text" } } },
      },
    });
  });

  it("leaves the design out with --only conventions", async () => {
    await files({ "better-supabase.config.json": json({}) });

    const result = await run([
      "apply",
      "--preset",
      await designUrl(),
      "--only",
      "conventions",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(0);
    expect(
      await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
    ).not.toContain("appTables");
  });
});

describe("add <block>", () => {
  it("lists the block, writes its modules, wires its client and names its glue", async () => {
    await files({
      "package.json": json({ name: "app", dependencies: { next: "16" } }),
      "better-supabase.config.json": json({ blocks: {} }),
      "lib/blocks.ts": [
        'import { createBlocks, rpcTransport } from "better-supabase/blocks";',
        'import { profilesBlock } from "better-supabase/blocks/profiles";',
        "",
        "export function blocks(supabase) {",
        "  return createBlocks(",
        "    { transport: rpcTransport(supabase) },",
        "    {",
        "      profiles: profilesBlock,",
        "    },",
        "  );",
        "}",
        "",
      ].join("\n"),
    });
    const result = await run(["add", "outbox", "comments", "--cwd", dir]);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Wired comments, outbox in lib/blocks.ts.");
    expect(result.stdout).toContain(
      "Glue for next: npx shadcn@latest add @better-supabase/outbox @better-supabase/outbox-relay-next",
    );
    const wiring = await readFile(join(dir, "lib/blocks.ts"), "utf-8");
    expect(wiring).toContain(
      'import { profilesBlock } from "better-supabase/blocks/profiles";\nimport { commentsBlock } from "better-supabase/blocks/comments";',
    );
    expect(wiring).toContain(
      "      profiles: profilesBlock,\n      comments: commentsBlock,\n      outbox: outboxBlock,\n",
    );
    expect(
      JSON.parse(
        await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
      ).blocks,
    ).toMatchObject({ comments: {}, outbox: {} });
  });

  it("prints the wiring without lib/blocks.ts, and stops on an unknown block", async () => {
    await files({
      "package.json": json({ name: "app" }),
      "better-supabase.config.json": json({}),
    });
    const result = await run(["add", "tags", "--dry-run", "--cwd", dir]);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      "Wire the clients in lib/blocks.ts (it doesn't exist yet):",
    );
    expect(result.stdout).toContain(
      'import { tagsBlock } from "better-supabase/blocks/tags";  // tags: tagsBlock',
    );
    expect((await run(["add", "nope", "--cwd", dir])).code).toBe(2);
  });
});

describe("init --preset", () => {
  it("writes the config with the preset, the modules and lib/blocks.ts", async () => {
    await files({
      "package.json": json({ name: "app", dependencies: { next: "16" } }),
    });
    const result = await run(["init", "--preset", "minimal", "--cwd", dir]);
    expect(result.code).toBe(0);

    const config = await readFile(
      join(dir, "better-supabase.config.ts"),
      "utf-8",
    );

    expect(config).toContain("  preset: 'minimal',\n  casing: 'snake',");
    expect(await readFile(join(dir, "lib/blocks.ts"), "utf-8")).toContain(
      "profiles: profilesBlock,",
    );
    expect(
      existsSync(
        join(dir, "supabase/schemas/900_better_supabase_22_profiles.sql"),
      ),
    ).toBe(true);
  });

  it("writes a code for a selection, and refuses what can't install", async () => {
    await files({ "package.json": json({ name: "app" }) });
    const code = encodePreset({ blocks: ["tags"], integrations: ["mcp"] });

    const result = await run([
      "init",
      "--preset",
      code,
      "--dry-run",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      "Would write supabase/functions/mcp/index.ts",
    );
    expect(result.stdout).toContain("(tags)");

    const blocked = await run([
      "init",
      "--preset",
      encodePreset({ blocks: ["teams"], scope: "user" }),
      "--cwd",
      dir,
    ]);

    expect(blocked.code).toBe(2);
    expect(blocked.stderr).toContain("The preset can't install: teams");
    expect(
      (await run(["init", "--preset", "startup", "--cwd", dir])).code,
    ).toBe(2);
  });

  it("writes a design's app tables and extra columns from a /create URL", async () => {
    await files({ "package.json": json({ name: "app" }) });

    const stray = await run([
      "init",
      "--preset",
      await designUrl({ extraColumns: { organizations: { tier: "text" } } }),
      "--cwd",
      dir,
    ]);

    expect(stray.code).toBe(2);
    expect(stray.stderr).toContain(
      "the preset doesn't install the organizations block",
    );

    const result = await run([
      "init",
      "--preset",
      await designUrl(),
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(0);

    const config = await readFile(
      join(dir, "better-supabase.config.ts"),
      "utf-8",
    );

    expect(config).toContain(
      "        extraColumns: {\n          nickname: 'text',",
    );
    expect(config).toContain("notes: {");
    expect(config).not.toContain("positions");

    const sql = await readFile(join(dir, APP_TABLES_FILE), "utf-8");
    expect(sql).toContain('"public"."notes"');
    expect(
      await readFile(
        join(dir, "supabase/schemas/900_better_supabase_22_profiles.sql"),
        "utf-8",
      ),
    ).toContain("nickname");
  });
});
