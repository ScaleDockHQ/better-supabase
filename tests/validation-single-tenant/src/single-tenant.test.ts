import { run } from "better-supabase/cli";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, isGenerated, readTree } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const upgraded = async (): Promise<{
  readonly dir: string;
  readonly tree: ReadonlyMap<string, string>;
}> => {
  const dir = await copyFixture();

  dirs.push(dir);

  expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });

  return { dir, tree: await readTree(dir) };
};

// The first command loads the CLI from source, which takes about 5 s on a CI
// runner.
const TIMEOUT = 60_000;

// Everything that names a tenant: the column, the helper functions, the
// membership tables and the organization-scoped policies.
const TENANT = /tenant|organization|membership|member_ids|team_id|\bteams?\b/i;

describe("an app with no organizations", () => {
  it(
    "gets no tenant column, helper or policy from the modules it uses",
    { timeout: TIMEOUT },
    async () => {
      const { tree } = await upgraded();

      const generated = [...tree].filter(([path]) => isGenerated(path));

      expect(generated.length).toBeGreaterThan(0);

      for (const [path, text] of generated) {
        expect({ path, tenant: TENANT.exec(text)?.[0] }).toStrictEqual({
          path,
          tenant: undefined,
        });
      }

      expect(
        tree.has("supabase/schemas/900_better_supabase_004_memberships.sql"),
      ).toBe(false);
    },
  );

  it(
    "protects the profile with owner-based policies",
    { timeout: TIMEOUT },
    async () => {
      const { tree } = await upgraded();

      const profiles = tree.get(
        "supabase/schemas/900_better_supabase_022_profiles.sql",
      );

      expect(profiles).toContain('"user_id" = (select auth.uid())');
      expect(profiles).toContain("create policy bsb_profiles_read");
    },
  );

  it(
    "keeps the app's owner policies and a second upgrade changes nothing",
    { timeout: TIMEOUT },
    async () => {
      const { dir, tree } = await upgraded();
      const app = tree.get("supabase/schemas/010_app.sql") ?? "";

      expect(app).toContain("create policy todos_owner_select");

      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });
      expect(await readTree(dir)).toStrictEqual(tree);

      expect(await run(["upgrade", "--check", "--cwd", dir])).toMatchObject({
        code: 0,
      });
    },
  );

  it("passes the ownership rules of doctor", { timeout: TIMEOUT }, async () => {
    // The fixture has no baseline migration, so BS376 and BS377 (schema
    // coverage) stay out; validation-declarative holds them.
    const { dir } = await upgraded();

    const result = await run([
      "doctor",
      "--only",
      "BS369,BS370,BS371,BS372,BS373,BS374,BS375,BS378,BS380,BS622",
      "--fail-on",
      "warning",
      "--snapshot",
      join(dir, "snapshot.json"),
      "--cwd",
      dir,
    ]);

    expect(result).toMatchObject({ code: 0 });
  });
});
