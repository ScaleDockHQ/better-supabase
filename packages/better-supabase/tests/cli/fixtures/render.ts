import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import { renderFiles } from "../../../src/cli/commands/gen.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type BetterSupabaseConfig,
  jsonSchema,
  resolveConfig,
  valibot,
  zod,
} from "../../../src/config/index.ts";
import { libraryFixture } from "./library.ts";

const fixtureConfig: BetterSupabaseConfig = {
  output: "tests/fixtures/generated.ts",
  json: {
    "customers.metadata": {
      type: "{ source?: string; tier?: 'free' | 'pro' }",
    },
  },
  plugins: {
    timestamps: true,
    softDelete: { column: "archived_at" },
    tenant: { column: "organization_id" },
    actor: true,
  },
  buckets: {
    customerLogos: {
      path: "{orgId}/{customerId}/logo/{version}.webp",
      public: true,
      policy: "tenant",
      fileSizeLimit: "5MiB",
      allowedMimeTypes: ["image/png", "image/jpeg", "image/webp"],
    },
  },
  storagePaths: { "customers.logo_path": "customerLogos" },
  topics: {
    notifications: "org:{orgId}:notifications:{userId}",
    customers: "org:{orgId}:customers",
  },
};

const here = (name: string): string =>
  fileURLToPath(new URL(name, libraryFixture("")));

export async function loadFixtureSnapshot(): Promise<Snapshot> {
  return parseSnapshot(
    JSON.parse(await readFile(here("./snapshot.json"), "utf8")),
    "tests/fixtures/snapshot.json",
  );
}

/** The fixture modules, rendered by `gen` with the runtime imported from source. */
export async function renderFixtures(): Promise<
  { path: string; contents: string }[]
> {
  const snapshot = await loadFixtureSnapshot();
  const root = here("../..");
  const variants: BetterSupabaseConfig[] = [
    { ...fixtureConfig, casing: "snake" },
    {
      ...fixtureConfig,
      casing: "camel",
      output: "tests/fixtures/generated-camel.ts",
      generators: [zod(), valibot(), jsonSchema()],
    },
  ];
  const files = new Map<string, string>();
  for (const variant of variants) {
    const rendered = await renderFiles(resolveConfig(variant, root), snapshot, {
      runtimeImport: "../../src/index.ts",
    });
    for (const file of rendered) {
      files.set(resolve(root, file.path), file.contents);
    }
  }
  return [...files].map(([path, contents]) => ({ path, contents }));
}
