import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import {
  agentsBlockFile,
  agentsBlockText,
  withAgentsBlock,
} from "../../src/cli/agents-block.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

async function project(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "bsb-agents-"));
  dirs.push(dir);

  return dir;
}

describe("the AGENTS.md block", () => {
  it("adds the block after the existing text and keeps that text", () => {
    const next = withAgentsBlock("# Mine\n\nRules.\n");

    expect(next.startsWith("# Mine\n\nRules.\n\n")).toBe(true);
    expect(next.endsWith(agentsBlockText())).toBe(true);
  });

  it("replaces only what sits between the markers, so a second run changes nothing", () => {
    const once = withAgentsBlock("# Mine\n");

    const edited = once.replace(
      "## better-supabase",
      "## better-supabase (old)",
    );

    const again = withAgentsBlock(`${edited}\nAfter.\n`);

    expect(again).toContain("# Mine");
    expect(again).toContain("After.");
    expect(again).not.toContain("(old)");
    expect(withAgentsBlock(again)).toBe(again);
  });

  it("starts a file when there is none", () => {
    expect(withAgentsBlock(undefined)).toBe(
      `# Agent guide\n\n${agentsBlockText()}`,
    );
  });

  it("plans nothing for a project without agent files, and a write for one with them", async () => {
    const bare = await project();
    expect(await agentsBlockFile(bare)).toBeUndefined();

    const cursor = await project();
    await mkdir(join(cursor, ".cursor"));
    expect(await agentsBlockFile(cursor)).toMatchObject({ path: "AGENTS.md" });

    const claude = await project();
    await writeFile(join(claude, "CLAUDE.md"), "@AGENTS.md\n");
    expect((await agentsBlockFile(claude))?.contents).toContain(
      "better-supabase-agent-rules",
    );
  });
});
