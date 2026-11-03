import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { apiUsedNames } from "../../src/cli/api-used.ts";
import { resolveConfig } from "../../src/config/index.ts";

async function project(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bsb-api-used-"));
  await mkdir(join(root, "src/lib/supabase"), { recursive: true });
  await writeFile(
    join(root, "src/page.ts"),
    `await db.$rpc("flag_definitions", {});`,
  );
  await writeFile(
    join(root, "src/lib/supabase/database.types.ts"),
    `export type F = "unused_helper";`,
  );

  return root;
}

describe("apiUsedNames", () => {
  it("is undefined unless gen.api.expose is used", async () => {
    const root = await project();

    expect(await apiUsedNames(resolveConfig({}, root))).toBeUndefined();
    expect(
      await apiUsedNames(
        resolveConfig({ gen: { api: { expose: "all" } } }, root),
      ),
    ).toBeUndefined();
  });

  it("reads the names the sources use, leaves the generated folder out and adds exposeAlso", async () => {
    const root = await project();

    const used = await apiUsedNames(
      resolveConfig(
        { gen: { api: { expose: "used", exposeAlso: ["from_config"] } } },
        root,
      ),
    );

    expect(used).toContain("flag_definitions");
    expect(used).toContain("from_config");
    expect(used).not.toContain("unused_helper");
  });
});
