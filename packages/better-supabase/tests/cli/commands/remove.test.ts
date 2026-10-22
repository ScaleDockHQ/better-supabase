import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

const WIRING =
  'import { createBlocks } from "better-supabase/blocks";\n\nexport const blocks = createBlocks({ transport }, {});\n';

const AUDIT_SCHEMA = "supabase/schemas/900_better_supabase_03_audit.sql";

describe("remove", () => {
  let dir: string;

  const config = async () =>
    JSON.parse(
      await readFile(join(dir, "better-supabase.config.json"), "utf-8"),
    ) as { blocks: string[] };

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-remove-"));
    await mkdir(join(dir, "lib"), { recursive: true });
    await writeFile(join(dir, "lib/blocks.ts"), WIRING);
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: [] }),
    );
    const added = await run(["add", "audit", "--cwd", dir]);

    if (added.code !== 0) {
      throw new Error(`add audit failed: ${added.stderr}`);
    }
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("takes a block out of the config, lib/blocks.ts and the schema files", async () => {
    expect(await readFile(join(dir, "lib/blocks.ts"), "utf-8")).toContain(
      "auditBlock",
    );
    expect(existsSync(join(dir, AUDIT_SCHEMA))).toBe(true);

    const result = await run(["remove", "audit", "--json", "--cwd", dir]);

    const envelope = JSON.parse(result.stdout) as {
      data: { blocks: string[]; removed: string[] };
      next: { command: string }[];
    };

    expect(result.code).toBe(0);
    expect(envelope.data.blocks).toEqual(["audit"]);
    expect(envelope.data.removed).toContain(AUDIT_SCHEMA);
    expect(envelope.next[0]?.command).toBe(
      "better-supabase db diff -f remove_audit",
    );
    expect((await config()).blocks).not.toContain("audit");
    expect(await readFile(join(dir, "lib/blocks.ts"), "utf-8")).toBe(WIRING);
    expect(existsSync(join(dir, AUDIT_SCHEMA))).toBe(false);
  });

  it("writes nothing with --dry-run", async () => {
    const result = await run(["remove", "audit", "--dry-run", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Dry run: nothing written.");
    expect((await config()).blocks).toContain("audit");
    expect(existsSync(join(dir, AUDIT_SCHEMA))).toBe(true);
  });

  it("refuses no names, unknown names and a block another one requires", async () => {
    expect((await run(["remove", "--cwd", dir])).stderr).toContain(
      "Name the blocks to remove",
    );

    const unknown = await run(["remove", "nope", "--cwd", dir]);

    expect(unknown.code).toBe(2);
    expect(unknown.stderr).toContain("nope isn't in blocks");

    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: ["memberships", "invitations"] }),
    );

    const required = await run(["remove", "memberships", "--cwd", dir]);

    expect(required.code).toBe(2);
    expect(required.stderr).toContain("memberships is required by invitations");
  });

  it("names the wiring it can't edit and the config it can't change", async () => {
    await writeFile(join(dir, "lib/blocks.ts"), "export const blocks = 1;\n");

    const unwired = await run(["remove", "audit", "--cwd", dir]);

    expect(unwired.code).toBe(0);
    expect(unwired.stdout).toContain(
      "Take audit out of lib/blocks.ts yourself",
    );

    await rm(join(dir, "better-supabase.config.json"));
    await writeFile(
      join(dir, "better-supabase.config.ts"),
      "const shared = { audit: {} };\n\nexport default { blocks: shared };\n",
    );

    const refused = await run(["remove", "audit", "--cwd", dir]);

    expect(refused.code).toBe(2);
    expect(refused.stderr).toContain("wasn't changed");
  });
});
