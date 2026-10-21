import type { BlocksConfig } from "better-supabase/config";

import { run } from "better-supabase/cli";
import { decodePreset, encodePreset } from "better-supabase/preset";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

// The blocks the CRM already has tables for. `apply --adopt` maps them onto
// those tables, and their requirements (updated-at, tenant) stay managed.
const PRESET = encodePreset({
  scope: "tenant",
  blocks: ["organizations", "profiles", "teams"],
});

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "validation-crm-adopt-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const committed = async (): Promise<{ blocks: unknown }> =>
  JSON.parse(
    await readFile(join(ROOT, "better-supabase.config.json"), "utf-8"),
  ) as { blocks: unknown };

describe("apply --adopt on the CRM schema", () => {
  it("proposes the adopt mappings the config holds", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        source: { snapshot: join(ROOT, "snapshot.json") },
        casing: "camel",
        blocks: ["read-sets"],
      }),
    );

    const result = await run([
      "apply",
      "--preset",
      PRESET,
      "--only",
      "blocks",
      "--adopt",
      "--dry-run",
      "--json",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(0);

    const { data } = JSON.parse(result.stdout) as {
      data: { adopted: Record<string, { mode: string }>; contents: string };
    };

    expect(Object.keys(data.adopted)).toEqual([
      "access",
      "organizations",
      "profiles",
      "teams",
    ]);
    const proposed = JSON.parse(data.contents) as { blocks: unknown };
    expect(proposed.blocks).toEqual((await committed()).blocks);
  });

  it("maps profiles onto user_id and the CRM's organization_id tenant column", async () => {
    const { blocks } = (await committed()) as {
      blocks: Record<string, { columns?: unknown }>;
    };

    expect(blocks["profiles"]?.columns).toMatchObject({
      profiles: { key: "user_id" },
    });
    expect(blocks["teams"]?.columns).toEqual({
      teams: { tenant: "organization_id" },
      members: { tenant: "organization_id" },
    });
  });

  it("keeps the CRM's own table names under a workspace tenant name", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        source: { snapshot: join(ROOT, "snapshot.json") },
        casing: "camel",
        blocks: ["read-sets"],
      }),
    );

    const result = await run([
      "apply",
      "--preset",
      encodePreset({
        scope: "tenant",
        tenantName: "workspace",
        blocks: ["organizations", "profiles", "teams"],
      }),
      "--adopt",
      "--dry-run",
      "--json",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(0);

    const { data } = JSON.parse(result.stdout) as {
      data: { adopted: BlocksConfig; contents: string };
    };

    const proposed = JSON.parse(data.contents) as { preset: string };
    expect(decodePreset(proposed.preset).preset.tenantName).toBe("workspace");

    // The CRM's tables keep their names: adopted tables are named in the
    // config, and only the managed blocks' default names follow blocks.tenant.entities.
    const { blocks } = (await committed()) as { blocks: BlocksConfig };

    expect(data.adopted).toEqual({
      access: blocks.access,
      organizations: blocks.organizations,
      profiles: blocks.profiles,
      teams: blocks.teams,
    });
  });

  it("finds nothing more to adopt once the config holds the mappings", async () => {
    const result = await run([
      "apply",
      "--preset",
      PRESET,
      "--only",
      "blocks",
      "--adopt",
      "--dry-run",
      "--cwd",
      ROOT,
    ]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain("already holds the preset");
  });
});
