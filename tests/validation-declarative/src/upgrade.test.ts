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
      const extension = join(dir, "supabase/schemas/020_app_extensions.sql");
      const edited = `${before.get("supabase/schemas/020_app_extensions.sql")}\ncomment on table public.projects is 'The app''s projects.';\n`;

      await writeFile(extension, edited);

      expect(await upgrade(dir)).toMatchObject({ code: 0 });

      const after = await readTree(dir);

      expect(Object.fromEntries(after)).toStrictEqual({
        ...Object.fromEntries(before),
        "supabase/schemas/020_app_extensions.sql": edited,
      });

      const app = [...after]
        .filter(([path]) => !isGenerated(path) && path.endsWith(".sql"))
        .map(([, text]) => text)
        .join("\n");

      for (const object of [
        "create policy projects_member_select",
        "create policy projects_member_write",
        "create trigger projects_reject_archived_rename",
        "alter table public.memberships add column invited_by",
        "create unique index organizations_slug_key",
        "create view public.my_organizations",
      ]) {
        expect(app).toContain(object);
      }
    },
  );
});
