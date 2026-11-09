import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { schemaModulePath } from "../../src/cli/gen/emit.ts";
import { moduleLayoutFor } from "../../src/cli/sql-layout.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("the files the layout reads", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-layout-order-"));
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await mkdir(join(root, "supabase/schemas"), { recursive: true });

    await writeFile(
      join(root, "supabase/config.toml"),
      '[db.migrations]\nschema_paths = ["./schemas/*.sql"]\n',
    );

    await writeFile(
      join(root, "supabase/migrations/20260101000000_old.sql"),
      "select better_supabase.audit('better_supabase.api_keys', ignore => '{window_start}');\n",
    );

    await writeFile(
      join(root, "supabase/schemas/010_audit.sql"),
      "select better_supabase.audit('better_supabase.api_keys', ignore => '{window_started_at}');\n",
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("lets the schema file, the final state, win over an older migration", async () => {
    const layout = await moduleLayoutFor(resolveConfig({}, root), {
      names: ["audit"],
    });

    expect(layout.auditedTables).toEqual([
      {
        target: "better_supabase.api_keys",
        ignore: ["window_started_at"],
        redact: [],
      },
    ]);
  });
});

describe("schemaModulePath", () => {
  it("names the server schema generated-schema.ts beside generated.ts and schema.ts", () => {
    expect(schemaModulePath("src/lib/supabase/generated.ts")).toBe(
      "src/lib/supabase/generated-schema.ts",
    );
    expect(schemaModulePath("src/lib/supabase/schema.ts")).toBe(
      "src/lib/supabase/generated-schema.ts",
    );
    expect(schemaModulePath("schema.ts")).toBe("generated-schema.ts");
  });
});
