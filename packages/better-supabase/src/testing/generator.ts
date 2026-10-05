import type { SchemaMeta } from "../schema/types.ts";

import {
  type Generator,
  type GeneratorInput,
  type GeneratorModel,
  type ResolvedConfig,
  resolveConfig,
} from "../config/index.ts";
import { isList } from "../core/guards.ts";
import {
  type ConformanceReport,
  conform,
  expect,
  frozenCopy,
  hasName,
  same,
} from "./conformance.ts";

function relativeImport(from: string, to: string): string {
  const fromParts = from.split("/").slice(0, -1);
  const toParts = to.split("/");
  let common = 0;
  while (common < fromParts.length && fromParts[common] === toParts[common])
    common += 1;
  const path = [
    ...Array.from({ length: fromParts.length - common }, () => ".."),
    ...toParts.slice(common),
  ].join("/");
  return path.startsWith(".") ? path : `./${path}`;
}

export interface TestGeneratorOptions {
  /** Schema metadata to generate from: `schema.meta` from your generated module. */
  readonly meta: SchemaMeta;
  /** Typegen metadata; defaults to an empty database. */
  readonly introspection?: GeneratorInput["introspection"];
  readonly extras?: GeneratorInput["extras"];
  readonly config?: ResolvedConfig;
  /** Defaults to one built from `meta`, with `unknown` for column types it can't name. */
  readonly model?: GeneratorModel;
}

/** A `GeneratorModel` from schema metadata, for generators tested without a database. */
function modelFromMeta(meta: SchemaMeta): GeneratorModel {
  return {
    tables: Object.values(meta.tables).map((table) => ({
      key: table.key,
      schema: table.schema,
      name: table.name,
      casing: meta.casing,
      columns: Object.entries(table.columns).map(([app, column]) => ({
        app,
        db: column.db,
        tsType: column.enum
          ? column.enum.map((value) => JSON.stringify(value)).join(" | ")
          : "unknown",
        nullable: column.nullable,
        optional:
          column.nullable || column.hasDefault || column.generated === true,
        readonly: column.generated === true,
        values: column.enum,
        json: column.json === true,
      })),
    })),
    enums: Object.entries(meta.enums).map(([name, values]) => ({
      schema: "public",
      name,
      values,
    })),
  };
}

const EMPTY_INTROSPECTION: GeneratorInput["introspection"] = {
  version: 1,
  schemas: [],
  tables: [],
  foreignTables: [],
  views: [],
  materializedViews: [],
  columns: [],
  primaryKeys: [],
  relationships: [],
  functions: [],
  types: [],
};

/** Proves a `Generator` writes relative, unique paths, is deterministic and doesn't mutate its input. */
export function testGenerator(
  generator: Generator,
  options: TestGeneratorOptions,
): Promise<ConformanceReport> {
  const config = options.config ?? resolveConfig({}, "/project");
  const input = (): GeneratorInput => ({
    meta: frozenCopy(options.meta),
    introspection: frozenCopy(options.introspection ?? EMPTY_INTROSPECTION),
    extras: frozenCopy(
      options.extras ?? { tables: [], buckets: [], realtime: [] },
    ),
    config,
    output: `${config.root}/${config.output}`,
    importPath: (from, to) => relativeImport(from, to),
    model: frozenCopy(options.model ?? modelFromMeta(options.meta)),
  });
  return conform(`Generator "${generator.name}"`, [
    hasName(generator),
    [
      "targets generator API 1",
      () => {
        const version: unknown = generator.apiVersion;
        expect(
          version === undefined || version === 1,
          `apiVersion is ${String(version)}; this better-supabase supports 1`,
        );
      },
    ],
    [
      "writes files inside the project",
      async () => {
        const files = await generator.generate(input());
        expect(isList(files), "generate() must return an array");
        for (const file of files) {
          expect(
            typeof file.path === "string" && typeof file.contents === "string",
            "files need a path and contents",
          );
          expect(
            !file.path.startsWith("/") && !/^[A-Za-z]:/.test(file.path),
            `${file.path} must be relative`,
          );
          expect(
            !file.path.split(/[\\/]/).includes(".."),
            `${file.path} must stay inside the project`,
          );
        }
        const paths = files.map((file) => file.path);
        expect(new Set(paths).size === paths.length, "paths must be unique");
      },
    ],
    [
      "is deterministic and does not mutate its input",
      async () => {
        const first = await generator.generate(input());
        const second = await generator.generate(input());
        expect(same(first, second), "two runs on the same input differ");
      },
    ],
  ]);
}
