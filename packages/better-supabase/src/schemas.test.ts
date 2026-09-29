import { readdir, readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';

import type { Snapshot } from './cli/introspect/types.ts';

import { formatReport } from './cli/doctor/format.ts';
import { RULES, runRules } from './cli/doctor/rules.ts';
import { generatorJsonSchema } from './cli/introspect/typegen.ts';
import { parseTomlSubset } from './cli/supabase-toml.ts';
import { resolveConfig } from './config/index.ts';
import fixture from './fixtures/snapshot.json' with { type: 'json' };

type Schema = Readonly<Record<string, unknown>>;

const SCHEMAS = new URL('../schemas/', import.meta.url);
const load = async (name: string): Promise<Schema> =>
  JSON.parse(await readFile(new URL(name, SCHEMAS), 'utf8')) as Schema;

const typeOf = (value: unknown): string => {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  return typeof value;
};

/** Enough of JSON Schema 2020-12 for the shipped schemas: type, enum, const, $ref, properties, items, oneOf. */
function validate(
  root: Schema,
  schema: Schema,
  value: unknown,
  path: string,
  errors: string[],
): void {
  if (typeof schema['$ref'] === 'string') {
    const target = (schema['$ref'] as string)
      .replace(/^#\//, '')
      .split('/')
      .reduce<unknown>((node, key) => (node as Schema)[key], root) as Schema;
    validate(root, target, value, path, errors);
  }
  if (Array.isArray(schema['oneOf'])) {
    const matches = (schema['oneOf'] as Schema[]).filter((option) => {
      const inner: string[] = [];
      validate(root, option, value, path, inner);
      return inner.length === 0;
    });
    if (matches.length !== 1)
      errors.push(`${path}: matches ${matches.length} oneOf options`);
  }
  if ('const' in schema && value !== schema['const'])
    errors.push(`${path}: expected ${JSON.stringify(schema['const'])}`);
  if (
    Array.isArray(schema['enum']) &&
    !(schema['enum'] as unknown[]).includes(value)
  ) {
    errors.push(
      `${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema['enum'])}`,
    );
  }
  if (schema['type'] !== undefined) {
    const types = ([] as unknown[]).concat(schema['type']);
    const actual = typeOf(value);
    if (
      !types.includes(actual) &&
      !(actual === 'integer' && types.includes('number'))
    ) {
      errors.push(`${path}: expected ${types.join(' | ')}, got ${actual}`);
      return;
    }
  }
  if (typeOf(value) === 'object') {
    const object = value as Record<string, unknown>;
    const properties = (schema['properties'] ?? {}) as Record<string, Schema>;
    for (const key of (schema['required'] ?? []) as string[]) {
      if (!(key in object)) errors.push(`${path}: missing ${key}`);
    }
    for (const [key, item] of Object.entries(object)) {
      if (properties[key])
        validate(root, properties[key], item, `${path}.${key}`, errors);
      else if (schema['additionalProperties'] === false)
        errors.push(`${path}: unexpected ${key}`);
    }
  }
  if (Array.isArray(value) && schema['items']) {
    value.forEach((item, index) =>
      validate(
        root,
        schema['items'] as Schema,
        item,
        `${path}[${index}]`,
        errors,
      ),
    );
  }
}

async function errorsFor(name: string, value: unknown): Promise<string[]> {
  const schema = await load(name);
  const errors: string[] = [];
  validate(schema, schema, value, '$', errors);
  return errors;
}

describe('shipped JSON Schemas', () => {
  it('have an $id matching their file and are referenced by the code', async () => {
    const files = (await readdir(SCHEMAS)).filter((file) =>
      file.endsWith('.json'),
    );
    expect(files.toSorted((a, b) => a.localeCompare(b))).toEqual([
      'config-v1.json',
      'doctor-report-v1.json',
      'snapshot-v2.json',
    ]);
    for (const file of files) {
      expect((await load(file))['$id']).toBe(
        `https://unpkg.com/better-supabase/schemas/${file}`,
      );
    }
  });

  it('describe the fixture snapshot', async () => {
    expect(await errorsFor('snapshot-v2.json', fixture)).toEqual([]);
    const [first] = fixture.extras.tables;
    const broken = {
      ...fixture,
      extras: {
        ...fixture.extras,
        tables: [
          {
            ...first,
            foreignKeys: [
              { name: 'fk', onDelete: 'explode', onUpdate: 'cascade' },
            ],
            extra: 1,
          },
        ],
      },
    };
    expect(await errorsFor('snapshot-v2.json', broken)).toEqual([
      '$.extras.tables[0].foreignKeys[0].onDelete: "explode" is not one of ["no action","restrict","cascade","set null","set default"]',
      '$.extras.tables[0]: unexpected extra',
    ]);
  });

  it('embed the postgrest-typegen metadata schema unchanged', async () => {
    const schema = (await load('snapshot-v2.json')) as {
      $defs: { generator: unknown };
    };
    expect(schema.$defs.generator).toEqual(generatorJsonSchema());
  });

  it('match the snapshot the examples and type tests generate from', async () => {
    const shared = await readFile(
      new URL('../../../supabase/snapshot.json', import.meta.url),
      'utf8',
    );
    expect(JSON.parse(shared)).toEqual(fixture);
  });

  it('describe doctor reports', async () => {
    const snapshot = structuredClone(fixture) as unknown as {
      generator: { tables: { schema: string; rls_enabled: boolean }[] };
    };
    snapshot.generator.tables.find(
      (table) => table.schema === 'public',
    )!.rls_enabled = false;
    const context = {
      config: resolveConfig({}, '/project'),
      snapshot: snapshot as unknown as Snapshot,
      configToml: {
        path: 'supabase/config.toml',
        text: '[auth]\njwt_expiry = 7200\n',
        document: parseTomlSubset('[auth]\njwt_expiry = 7200\n'),
        parser: 'builtin' as const,
      },
      envFiles: [{ path: '.env', text: 'SUPABASE_SECRET_KEY=x\n' }],
      gitignore: '',
      sources: [],
    };
    const findings = await runRules(
      context,
      RULES.filter((rule) => rule.code !== 'BS303'),
    );
    expect(findings.length).toBeGreaterThan(2);
    const report = JSON.parse(
      formatReport(findings, {
        format: 'json',
        rules: RULES,
        version: '0.0.0',
        fallbackFile: 'package.json',
      }),
    ) as unknown;
    expect(await errorsFor('doctor-report-v1.json', report)).toEqual([]);
  });

  it('describe a full config', async () => {
    const config = {
      $schema: 'https://unpkg.com/better-supabase/schemas/config-v1.json',
      source: { snapshot: 'supabase/snapshot.json' },
      schemas: ['public'],
      casing: 'camel',
      output: 'src/lib/supabase/generated.ts',
      postgrestVersion: '13',
      doctor: { ignore: ['BS204'], strict: true, sources: ['app/**/*.tsx'] },
    };
    expect(await errorsFor('config-v1.json', config)).toEqual([]);
    expect(
      await errorsFor('config-v1.json', { ...config, casing: 'kebab' }),
    ).toHaveLength(1);
  });
});
