import { run } from "better-supabase/cli";
import { rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture, isGenerated, readTree, ROOT } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const fresh = async (): Promise<string> => {
  const dir = await copyFixture();

  dirs.push(dir);

  return dir;
};

const upgrade = (dir: string) => run(["upgrade", "--cwd", dir]);

// The first command loads the CLI from source, which takes about 5 s on a CI
// runner.
const TIMEOUT = 60_000;

describe("upgrade on an app that owns its tables", () => {
  it(
    "finds the committed module files current",
    { timeout: TIMEOUT },
    async () => {
      const result = await run(["upgrade", "--check", "--cwd", ROOT]);

      expect(result).toMatchObject({ code: 0, stderr: "" });
    },
  );

  it(
    "writes the committed files from nothing and leaves the app's files alone",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh();
      const before = await readTree(dir);

      for (const path of before.keys()) {
        if (isGenerated(path)) {
          await rm(join(dir, path));
        }
      }

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const after = await readTree(dir);

      expect([...after.keys()].toSorted()).toStrictEqual(
        [...before.keys()].toSorted(),
      );

      expect(Object.fromEntries(after)).toStrictEqual(
        Object.fromEntries(before),
      );
    },
  );

  it(
    "preserves every app object across a second upgrade",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh();
      const before = await readTree(dir);

      await upgrade(dir);
      // A second run with an app edit in between: the app's file grows and the
      // generator neither rewrites it nor drops what it declares.
      const extension = join(dir, "supabase/schemas/060_grants.sql");
      const edited = `${before.get("supabase/schemas/060_grants.sql")}\ncomment on view public.job_attachments is 'The app''s job files.';\n`;

      await writeFile(extension, edited);

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const after = await readTree(dir);

      expect(Object.fromEntries(after)).toStrictEqual({
        ...Object.fromEntries(before),
        "supabase/schemas/060_grants.sql": edited,
      });

      const app = [...after]
        .filter(([path]) => !isGenerated(path) && path.endsWith(".sql"))
        .map(([, text]) => text)
        .join("\n");

      for (const object of [
        "create view public.job_attachments",
        "create trigger job_attachments_insert",
        "instead of insert on public.job_attachments",
        "create trigger lienlink_on_user_created",
        "after insert on auth.users",
        "create trigger jobs_audit",
        "add column job_id uuid generated always as",
        "add constraint jobs_team_fkey",
        "add constraint memberships_id_key",
        "add constraint teams_tenant_id_id_key",
        "grant select, insert on table public.job_attachments",
      ]) {
        expect(app).toContain(object);
      }

      // The stored generated column is the app's: no block function writes it.
      expect(
        after.get("supabase/schemas/900_better_supabase_034_attachments.sql"),
      ).not.toContain("job_id");
    },
  );
});
