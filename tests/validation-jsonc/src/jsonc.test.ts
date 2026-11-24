import { run } from "better-supabase/cli";
import { access, rm } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, isGenerated, readTree } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

// The first command loads the CLI from source, which takes about 5 s on a CI
// runner.
const TIMEOUT = 180_000;

describe("a project with only config.jsonc", () => {
  it(
    "has no config.toml, and upgrade writes the module files",
    { timeout: TIMEOUT },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      await expect(
        access(join(dir, "supabase", "config.toml")),
      ).rejects.toThrow("ENOENT");
      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });

      const generated = [...(await readTree(dir))].filter(([path]) =>
        isGenerated(path),
      );

      expect(generated.length).toBeGreaterThan(0);
      expect(
        generated.some(([path]) => path.startsWith("supabase/schemas/")),
      ).toBe(true);
    },
  );

  it(
    "reports no config problem and no migra warning in doctor",
    { timeout: TIMEOUT },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);
      await run(["upgrade", "--cwd", dir]);

      const result = await run(["doctor", "--json", "--cwd", dir]);
      const codes = result.stdout.match(/BS\d{3}/g) ?? [];

      expect(codes).not.toContain("BS316");
      expect(codes).not.toContain("BS711");
    },
  );
});
