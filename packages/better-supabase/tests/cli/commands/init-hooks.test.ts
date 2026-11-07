import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("init and the hooks framework", () => {
  let dir = "";

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-init-hooks-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const init = async (dependencies: Record<string, string>) => {
    await writeFile(
      join(dir, "package.json"),
      JSON.stringify({ name: "app", dependencies }),
    );

    expect(
      (await run(["init", "--preset", "minimal", "--cwd", dir])).code,
    ).toBe(0);

    return readFile(join(dir, "better-supabase.config.ts"), "utf-8");
  };

  it("writes gen.hooks for a framework no adapter selects", async () => {
    expect(await init({ vue: "3" })).toContain(
      "output: 'lib/supabase/generated.ts', hooks: 'vue' }",
    );
  });

  it("leaves it out when an adapter already selects the framework", async () => {
    expect(await init({ next: "16", react: "19" })).not.toContain("hooks:");
  });
});
