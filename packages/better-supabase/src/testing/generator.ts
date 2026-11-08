import type {
  Generator,
  GeneratorInput,
  GeneratorModel,
  ResolvedConfig,
} from "../config/index.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { ConformanceReport } from "./conformance.ts";

import { generatorProblem, resolveConfig } from "../config/index.ts";
import { isList } from "../core/guards.ts";
import { conform, expect, frozenCopy, same } from "./conformance.ts";
import { hasName } from "./kits/executor.ts";

export interface TestGeneratorPluginOptions {
  /** Schema metadata to generate from: `schema.meta` from your generated module. */
  readonly meta: SchemaMeta;
  /** Typegen metadata; defaults to an empty database. */
  readonly introspection?: GeneratorInput["introspection"];
  readonly extras?: GeneratorInput["extras"];
  readonly config?: ResolvedConfig;
  /** Where files import the runtime from. Defaults to `better-supabase`. */
  readonly runtime?: string;
  /**
   * Defaults to one built from `meta`, with `unknown` for column and function
   * types it can't name, and no blocks.
   */
  readonly model?: GeneratorModel;
}

/**
 * A `GeneratorModel` from schema metadata, for generators tested without a
 * database.
 */
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
        nullable: column.nullable === true,
        optional:
          column.nullable === true ||
          column.hasDefault === true ||
          column.generated === true,
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
    functions: Object.entries(meta.functions).flatMap(([key, fn]) =>
      (fn.overloads ?? [fn]).map((signature) => ({
        key,
        schema: fn.schema,
        args: signature.args.map((arg) => {
          const values = meta.enums[arg.type];

          return {
            name: arg.name,
            tsType:
              values === undefined
                ? "unknown"
                : values.map((value) => JSON.stringify(value)).join(" | "),
            optional: arg.optional === true,
            values,
          };
        }),
        returns: "unknown",
        returnsSet: signature.returnsSet,
        volatility: signature.volatility,
      })),
    ),
    blocks: [],
  };
}

const isFactory = (value: unknown): value is (options: unknown) => unknown =>
  typeof value === "function";

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

/**
 * Proves a `Generator` plugin follows the contract: it declares `apiVersion: 2`
 * and a version, writes relative unique paths, is deterministic, doesn't mutate
 * its input, reads only data that survives `structuredClone` (so it is safe on
 * a worker), builds again from its `module` to the same files when it names
 * one, and returns files that survive the JSON round trip the cache makes.
 */
export function testGeneratorPlugin(
  generator: Generator,
  options: TestGeneratorPluginOptions,
): Promise<ConformanceReport> {
  const config = options.config ?? resolveConfig({}, "/project");

  const input = (): GeneratorInput => ({
    meta: frozenCopy(options.meta),
    introspection: frozenCopy(options.introspection ?? EMPTY_INTROSPECTION),
    extras: frozenCopy(
      options.extras ?? { tables: [], buckets: [], realtime: [] },
    ),
    config: frozenCopy({
      output: config.output,
      databaseTypesOutput: config.databaseTypesOutput,
      casing: config.casing,
      json: config.json,
    }),
    imports: { runtime: options.runtime ?? "better-supabase" },
    model: frozenCopy(options.model ?? modelFromMeta(options.meta)),
  });

  return conform(`Generator "${generator.name}"`, [
    hasName(generator),
    [
      "targets generator API 2 and declares a version",
      () => {
        const problem = generatorProblem(generator);
        expect(problem === undefined, problem ?? "");
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
    [
      "reads only data that structuredClone copies (worker safe)",
      async () => {
        const fresh = await generator.generate(input());
        const cloned = await generator.generate(structuredClone(input()));
        expect(same(fresh, cloned), "a cloned input gives different files");
      },
    ],
    [
      "builds again from its module, to the same files (worker safe)",
      async () => {
        const { module } = generator;

        if (module === undefined) {
          return;
        }

        // Lazy: the module is the generator's own, named by the generator, as
        // `gen` loads it on a worker thread. Without a module there is nothing to load.
        const loaded: unknown = await import(module.specifier);

        const build: unknown =
          typeof loaded === "object" && loaded !== null
            ? Object.entries(loaded).find(([key]) => key === module.export)?.[1]
            : undefined;

        expect(
          isFactory(build),
          `${module.specifier} must export a function named "${module.export}"`,
        );

        const rebuilt: unknown = isFactory(build)
          ? build(generator.options ?? undefined)
          : undefined;

        expect(
          typeof rebuilt === "object" &&
            rebuilt !== null &&
            "name" in rebuilt &&
            rebuilt.name === generator.name &&
            "version" in rebuilt &&
            rebuilt.version === generator.version &&
            "generate" in rebuilt &&
            typeof rebuilt.generate === "function",
          "the module's export must build a generator with the same name and version",
        );

        const fresh = await generator.generate(input());
        // SAFETY: the check above found a generate function on `rebuilt`.
        const again = await (rebuilt as Generator).generate(input());
        expect(same(fresh, again), "the rebuilt generator writes other files");
      },
    ],
    [
      "gives the same files from the cache as from a fresh run",
      async () => {
        const fresh = await generator.generate(input());
        const stored: unknown = JSON.parse(JSON.stringify(fresh));
        expect(same(fresh, stored), "files do not survive the JSON round trip");

        if (generator.pure === true) {
          expect(
            same(
              generator.options ?? null,
              JSON.parse(JSON.stringify(generator.options ?? null)),
            ),
            "a pure generator's options must be JSON data: they key the cache",
          );
        }
      },
    ],
    [
      "writes the validators first when it provides them",
      async () => {
        if (generator.provides?.includes("validators") !== true) {
          return;
        }

        const [first] = await generator.generate(input());
        expect(
          first?.contents.includes("validators") === true,
          "the first file of a generator that provides validators exports `validators`",
        );
      },
    ],
  ]);
}
