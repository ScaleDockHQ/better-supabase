import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { withSettingsSchemas } from "../../src/cli/settings-schemas.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { standardSchema } from "../../src/generators/standard-schema/index.ts";

let dir: string | undefined;

afterEach(async () => {
  if (dir !== undefined) {
    await rm(dir, { recursive: true, force: true });
    dir = undefined;
  }
});

async function project(): Promise<string> {
  dir = await mkdtemp(join(tmpdir(), "bsb-settings-"));
  await writeFile(
    join(dir, "settings.ts"),
    "export const settings = { schemas: { user: {}, organization: {}, platform: {} } };\nexport const other = 1;\n",
  );

  return dir;
}

const generators = (settings: string) => ({
  gen: { generators: [standardSchema({ settings })] },
});

describe("withSettingsSchemas", () => {
  it("passes the named defineSettings result as the schemas option", async () => {
    const root = await project();

    const config = await withSettingsSchemas(
      resolveConfig(
        { blocks: ["settings"], ...generators("./settings.ts#settings") },
        root,
      ),
    );

    expect(config.blocks["settings"]?.options?.["schemas"]).toHaveProperty(
      "schemas",
    );
    expect(
      config.instances["settings"]?.config.options?.["schemas"],
    ).toHaveProperty("schemas");
  });

  it("keeps a schemas option the config sets", async () => {
    const root = await project();
    const own = { user: {} };

    const config = await withSettingsSchemas(
      resolveConfig(
        {
          blocks: { settings: { options: { schemas: own } } },
          ...generators("./settings.ts#settings"),
        },
        root,
      ),
    );

    expect(config.blocks["settings"]?.options?.["schemas"]).toBe(own);
  });

  it("leaves the config alone without the block or the option", async () => {
    const root = await project();
    const noOption = resolveConfig({ blocks: ["settings"] }, root);

    const noBlock = resolveConfig(
      { blocks: ["notifications"], ...generators("./settings.ts#settings") },
      root,
    );

    expect(await withSettingsSchemas(noOption)).toBe(noOption);
    expect(await withSettingsSchemas(noBlock)).toBe(noBlock);
  });

  it("refuses an export that is not a settings definition", async () => {
    const root = await project();

    await expect(
      withSettingsSchemas(
        resolveConfig(
          { blocks: ["settings"], ...generators("./settings.ts#other") },
          root,
        ),
      ),
    ).rejects.toThrow("defineSettings()");
    await expect(
      withSettingsSchemas(
        resolveConfig(
          { blocks: ["settings"], ...generators("./settings.ts") },
          root,
        ),
      ),
    ).rejects.toThrow("./path.ts#settings");
  });
});
