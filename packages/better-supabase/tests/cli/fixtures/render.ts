import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { renderFiles } from "../../../src/cli/gen/render.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { factories } from "../../../src/generators/factories.ts";
import { jsonSchema } from "../../../src/generators/json-schema.ts";
import { nuqs } from "../../../src/generators/nuqs.ts";
import { standardSchema } from "../../../src/generators/standard-schema.ts";
import { valibot } from "../../../src/generators/valibot.ts";
import { zod } from "../../../src/generators/zod.ts";
import { libraryFixture, snapshotPath } from "./library.ts";

const fixtureConfig: BetterSupabaseConfig = {
  gen: {
    // The runtime tests import `schema` and its tables from one module; the
    // default layout is covered by tests/cli/gen/render.test.ts and the examples.
    tableModules: false,
    blockModules: false,
    file: "tests/fixtures/generated.ts",
    json: {
      "customers.metadata": {
        type: "{ source?: string; tier?: 'free' | 'pro' }",
      },
    },
    storagePaths: { "customers.logo_path": "customerLogos" },
  },
  blocks: {
    "updated-at": {},
    "created-by": {},
    trash: { options: { deletedAt: "archived_at" } },
  },
  database: {
    buckets: {
      customerLogos: {
        path: "{organizationId}/{customerId}/logo/{version}.webp",
        public: true,
        policy: "tenant",
        fileSizeLimit: "5MiB",
        allowedMimeTypes: ["image/png", "image/jpeg", "image/webp"],
      },
    },
    topics: {
      notifications: "organization:{organizationId}:notifications:{userId}",
      customers: "organization:{organizationId}:customers",
    },
  },
  auth: { tenant: { column: "organization_id" } },
};

const here = (name: string): string =>
  fileURLToPath(new URL(name, libraryFixture("")));

export async function loadFixtureSnapshot(): Promise<Snapshot> {
  return parseSnapshot(
    JSON.parse(await readFile(snapshotPath, "utf-8")),
    "supabase/snapshot.json",
  );
}

/**
 * The fixture modules, rendered by `gen` with the runtime imported from source.
 * Their schemas stay bare, so each test installs the extensions it covers.
 */
export async function renderFixtures(): Promise<
  { path: string; contents: string }[]
> {
  const snapshot = await loadFixtureSnapshot();
  const root = here("../..");

  const variants: BetterSupabaseConfig[] = [
    { ...fixtureConfig, gen: { ...fixtureConfig.gen, casing: "snake" } },
    {
      ...fixtureConfig,
      gen: {
        ...fixtureConfig.gen,
        casing: "camel",
        file: "tests/fixtures/generated-camel.ts",
        generators: [
          zod(),
          zod({
            flavor: "mini",
            validators: false,
            output: "tests/fixtures/generated-camel.zod-mini.ts",
          }),
          valibot({ validators: false }),
          jsonSchema(),
          nuqs(),
          factories({ testingImport: "../../src/testing/index.ts" }),
          standardSchema({ validators: false }),
        ],
      },
    },
  ];

  const files = new Map<string, string>();

  for (const variant of variants) {
    const rendered = await renderFiles(resolveConfig(variant, root), snapshot, {
      runtimeImport: "../../src/index.ts",
      extensions: false,
    });

    for (const file of rendered.filter(
      ({ path }) =>
        !path.endsWith("blocks.generated.ts") &&
        !path.endsWith("blocks.config.ts"),
    )) {
      files.set(resolve(root, file.path), file.contents);
    }
  }

  return [...files].map(([path, contents]) => ({ path, contents }));
}
