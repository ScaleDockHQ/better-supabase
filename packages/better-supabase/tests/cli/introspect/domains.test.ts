import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { introspect } from "../../../src/cli/introspect/index.ts";
import { liteSource } from "../../../src/cli/introspect/lite.ts";
import { tsTypeOf } from "../../../src/cli/introspect/typegen.ts";
import { formatDomain } from "../../../src/cli/sql/format-domains.ts";
import { readSupabaseToml } from "../../../src/cli/supabase-toml.ts";

/** Replaying into PGlite takes seconds, more under coverage. */
describe("domain columns", { timeout: 60_000 }, () => {
  it("are typed as their base type by gen", async () => {
    const email = formatDomain("email", "text");
    const rating = formatDomain("rating", "integer");

    const root = await mkdtemp(join(tmpdir(), "bsb-domains-"));
    await writeFile(join(root, ".git"), "");
    await mkdir(join(root, "supabase/migrations"), { recursive: true });

    await writeFile(
      join(root, "supabase/config.toml"),
      '[db]\ndriver = "sqlite-postgres"\n',
    );

    await writeFile(
      join(root, "supabase/migrations/20260101000000_domains.sql"),
      `create schema bsb;\n${email?.sql}\n${rating?.sql}\ncreate table public.t (id uuid primary key, e bsb.email not null, r bsb.rating);`,
    );

    const source = await liteSource(
      root,
      await readSupabaseToml(root),
      "sqlite-postgres",
    );

    try {
      const snapshot = await introspect(source.queryable, ["public"]);

      const types = Object.fromEntries(
        snapshot.generator.columns
          .filter((column) => column.table === "t")
          .map((column) => [
            column.name,
            tsTypeOf(snapshot.generator, "public", column.format),
          ]),
      );

      expect(types).toEqual({ id: "string", e: "string", r: "number" });
    } finally {
      await source.close();
      await rm(root, { recursive: true, force: true });
    }
  });
});
