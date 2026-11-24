import { run } from "better-supabase/cli";
import { readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { copyFixture } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const TIMEOUT = 180_000;

// The blocks create their tables under their own names in `public`; the app
// only extends them with `alter table` (ADR 1190). No `tables` or `columns`
// entry names a default.
const CONFIG = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: [
    { block: "organizations", schema: "public" },
    { block: "memberships", schema: "public" },
    { block: "profiles", schema: "public" },
  ],
});
`;

describe("a block table under block names", () => {
  it(
    "is created by the block and extended by the app without a rewrite",
    { timeout: TIMEOUT },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      const schemas = join(dir, "supabase/schemas");

      for (const file of await readdir(schemas)) {
        await rm(join(schemas, file));
      }

      await writeFile(join(dir, "better-supabase.config.ts"), CONFIG);
      await writeFile(
        join(schemas, "010_app.sql"),
        `alter table public.organizations add column region text;
alter table public.organizations add constraint organizations_region_check check (region <> '');
`,
      );

      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });

      const text = (
        await Promise.all(
          (await readdir(schemas)).map((file) =>
            readFile(join(schemas, file), "utf-8"),
          ),
        )
      ).join("\n");

      expect(text).toMatch(
        /create table (if not exists )?"public"."organizations"/,
      );
      expect(text).not.toContain('organizations_region_check" check');
      expect(await run(["upgrade", "--check", "--cwd", dir])).toMatchObject({
        code: 0,
      });
      expect(await readFile(join(schemas, "010_app.sql"), "utf-8")).toContain(
        "add column region text",
      );
    },
  );

  it(
    "maps an app table that keeps its names with @bsb tags",
    { timeout: TIMEOUT },
    async () => {
      const dir = await copyFixture();

      dirs.push(dir);

      const schemas = join(dir, "supabase/schemas");
      const app = await readFile(join(schemas, "010_app.sql"), "utf-8");

      await writeFile(join(dir, "better-supabase.config.ts"), CONFIG);
      await writeFile(
        join(schemas, "010_app.sql"),
        `${app.replaceAll("public.memberships", "public.seats")}
comment on table public.seats is '@bsb block-table=memberships.memberships';
comment on column public.seats.organization_id is '@bsb column=tenant';
`,
      );

      expect(await run(["upgrade", "--cwd", dir])).toMatchObject({ code: 0 });

      const module = await readFile(
        join(schemas, "900_better_supabase_004_memberships.sql"),
        "utf-8",
      );

      expect(module).toContain('"public"."seats"');
      expect(module).not.toContain('"public"."memberships"');
    },
  );
});
