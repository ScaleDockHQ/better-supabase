import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  namingCodemod,
  renameMigrationSql,
} from "../../src/cli/codemod-naming.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("naming codemod edges", () => {
  it("leaves SQL objects the project never names, and an unknown kind", () => {
    expect(
      renameMigrationSql(
        [
          {
            kind: "constraint",
            from: "old_key",
            to: "new_key",
            table: "public.items",
            since: "0.58.0",
          },
        ],
        "select 1",
      ),
    ).toBeUndefined();

    expect(
      renameMigrationSql([
        { kind: "nope" as "type", from: "a", to: "b", since: "0.58.0" },
      ]),
    ).toContain("nope");
  });

  it("rewrites nothing when the config did not load", async () => {
    const codemod = namingCodemod();

    const rewrite = await codemod.files?.({
      config: resolveConfig({}, "/"),
      sql: [],
      configLoaded: false,
    });

    expect(rewrite?.("app.ts", "const kept = true;")).toEqual({
      text: "const kept = true;",
      review: [],
    });
  });

  it("asks for a history actor the config text does not set", async () => {
    const root = mkdtempSync(join(tmpdir(), "bsb-naming-"));

    mkdirSync(join(root, "supabase/schemas"), { recursive: true });
    writeFileSync(
      join(root, "supabase/schemas/history.sql"),
      "create table public.quote_history (id uuid primary key, actor_user_id uuid);\n",
    );

    const config = resolveConfig(
      {
        blocks: {
          "state-machine": {
            options: {
              machines: {
                quote: { history: { table: "public.quote_history" } },
              },
            },
          },
        },
      },
      root,
    );

    const codemod = namingCodemod();

    const rewrite = await codemod.files?.({
      config,
      sql: [],
      configLoaded: true,
      configFile: join(root, "better-supabase.config.ts"),
      configText: "export default { blocks: {} };\n",
    });

    const other = rewrite?.("src/app.ts", "export default { blocks: {} };\n");

    const edited = rewrite?.(
      join(root, "better-supabase.config.ts"),
      "export default { blocks: {} };\n",
    );

    expect(other?.text).toContain("blocks: {}");
    expect(
      edited?.review.some((hint) => hint.message.includes("actor_user_id")),
    ).toBe(true);
  });
});
