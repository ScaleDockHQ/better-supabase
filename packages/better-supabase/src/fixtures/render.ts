import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { Snapshot } from '../cli/introspect/types.ts';

import { parseSnapshot } from '../cli/commands/snapshot.ts';
import { emitModule } from '../cli/gen/emit.ts';
import { buildModel } from '../cli/gen/model.ts';
import { generateDatabaseTypes } from '../cli/introspect/typegen.ts';
import { importPath } from '../cli/io.ts';
import {
  type BetterSupabaseConfig,
  jsonSchema,
  resolveConfig,
  valibot,
  zod,
} from '../config/index.ts';

export const fixtureConfig: BetterSupabaseConfig = {
  output: 'src/fixtures/generated.ts',
  json: {
    'customers.metadata': {
      type: "{ source?: string; tier?: 'free' | 'pro' }",
    },
  },
  plugins: {
    timestamps: true,
    softDelete: { column: 'archived_at' },
    tenant: { column: 'organization_id', claim: 'org_id' },
    actor: true,
  },
  buckets: {
    customerLogos: {
      path: '{orgId}/{customerId}/logo/{version}.webp',
      policy: 'tenant',
      fileSizeLimit: '5MiB',
      allowedMimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    },
  },
  topics: {
    notifications: 'org:{orgId}:notifications:{userId}',
    customers: 'org:{orgId}:customers',
  },
};

const here = (name: string): string =>
  fileURLToPath(new URL(name, import.meta.url));

export async function loadFixtureSnapshot(): Promise<Snapshot> {
  return parseSnapshot(
    JSON.parse(await readFile(here('./snapshot.json'), 'utf8')),
    'src/fixtures/snapshot.json',
  );
}

/** The fixture modules, generated with the runtime imported from source. */
export async function renderFixtures(): Promise<
  { path: string; contents: string }[]
> {
  const snapshot = await loadFixtureSnapshot();
  const variants = [
    { file: './generated.ts', casing: 'snake' as const },
    { file: './generated-camel.ts', casing: 'camel' as const },
  ];
  const root = here('../..');
  const files = variants.map(({ file, casing }) => {
    const config = resolveConfig({ ...fixtureConfig, casing }, root);
    const model = buildModel(snapshot, config);
    return {
      path: here(file),
      contents: emitModule(model, {
        runtimeImport: '../index.ts',
        importPathFor: (from) => from,
      }),
    };
  });
  files.unshift({
    path: here('./database.types.ts'),
    contents: await generateDatabaseTypes(snapshot.generator, {
      schemas: ['public'],
      postgrestVersion: '13',
    }),
  });

  const config = resolveConfig(
    {
      ...fixtureConfig,
      casing: 'camel',
      output: 'src/fixtures/generated-camel.ts',
    },
    root,
  );
  const model = buildModel(snapshot, config);
  const input = {
    meta: model.meta,
    introspection: model.introspection,
    extras: snapshot.extras,
    config,
    output: resolve(root, config.output),
    importPath: (from: string, to: string) =>
      importPath(resolve(root, from), resolve(root, to)),
  };
  for (const generator of [zod(), valibot(), jsonSchema()]) {
    for (const file of await generator.generate(input)) {
      files.push({ path: resolve(root, file.path), contents: file.contents });
    }
  }
  return files;
}
