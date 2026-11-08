import { run } from "better-supabase/cli";
import { execFile } from "node:child_process";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, isGenerated, readTree, ROOT } from "./fixture.ts";

const SUPABASE = join(ROOT, "../../node_modules/.bin/supabase");

const exec = promisify(execFile);

// The CLI plans against a shadow database from the migrations, so no running
// stack is needed. A machine without the Supabase CLI skips the file.
const available = await exec(SUPABASE, ["--version"]).then(
  () => true,
  () => false,
);

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const sync = async (dir: string): Promise<string> => {
  const { stdout, stderr } = await exec(
    SUPABASE,
    ["db", "schema", "declarative", "sync", "--no-apply", "--strict-coverage"],
    // The first plan pulls the shadow database image on a cold runner; a stuck
    // run then fails with the CLI's own output instead of the test's timeout.
    { cwd: dir, timeout: 240_000 },
  );

  return `${stdout}${stderr}`;
};

describe.skipIf(!available)("the declarative sync after upgrade", () => {
  it(
    "is empty after the first and after a second upgrade",
    { timeout: 600_000 },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      for (const path of (await readTree(dir)).keys()) {
        if (isGenerated(path)) {
          await rm(join(dir, path));
        }
      }

      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });
      expect(await sync(dir)).toContain("No schema changes found");

      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });
      expect(await sync(dir)).toContain("No schema changes found");
    },
  );
});
