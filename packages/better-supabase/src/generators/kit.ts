import type {
  Generator,
  GeneratorCapability,
  GeneratedFile,
  GeneratorInput,
  GeneratorModule,
} from "../config/index.ts";

export type {
  Bounds,
  DocsSource,
  FieldDocs,
  FieldPlan,
  ScalarKind,
  SchemaSource,
  TableDocs,
  Variant,
} from "./shared.ts";

export type {
  ExtraSchema,
  ExtraSchemas,
  FieldMeta,
  ResultSchema,
} from "./extras.ts";

export {
  extraKinds,
  extraSchemas,
  fieldMeta,
  fieldMetaLines,
  objectType,
  resultType,
} from "./extras.ts";

export {
  fieldDocs,
  fieldSpec,
  fieldsFor,
  HEADER,
  optionalLine,
  parseCheckBounds,
  parseComment,
  parseImport,
  propertyKey,
  rowType,
  schemaName,
  siblingPath,
  tableDocs,
  tableEntries,
  temporalGuardImport,
  titleOf,
  variantsFor,
  variantTitle,
} from "./shared.ts";

export type {
  GeneratedFile,
  Generator,
  GeneratorBlock,
  GeneratorBlockEntity,
  GeneratorCapability,
  GeneratorColumn,
  GeneratorConfigView,
  GeneratorEntitySchemas,
  GeneratorField,
  GeneratorFunction,
  GeneratorImports,
  GeneratorInput,
  GeneratorModel,
  GeneratorModule,
  GeneratorTable,
} from "../config/index.ts";

/** The generator contract this release of `gen` runs. */
export const GENERATOR_API_VERSION = 2;

/** What `defineGenerator` takes: a `Generator` without its `apiVersion`. */
export interface GeneratorDefinition {
  readonly name: string;
  readonly version: string;
  readonly options?: unknown;
  readonly pure?: boolean;
  readonly workerSafe?: boolean;
  readonly module?: GeneratorModule;
  readonly provides?: readonly GeneratorCapability[];
  generate(
    input: GeneratorInput,
  ): readonly GeneratedFile[] | Promise<readonly GeneratedFile[]>;
}

/**
 * Declares a generator at the current contract. `gen` caches the files of a
 * `pure` generator on its name, version, options and input, and runs a
 * `workerSafe` one that is given as a module on a worker thread.
 */
export function defineGenerator(definition: GeneratorDefinition): Generator {
  return { apiVersion: GENERATOR_API_VERSION, ...definition };
}

/**
 * The import specifier from one generated file to another, both relative to the
 * project root: `./zod.ts`, `../lib/database.types.ts`.
 */
export function relativeImport(from: string, to: string): string {
  const fromParts = segments(from).slice(0, -1);
  const toParts = segments(to);
  let common = 0;

  while (
    common < fromParts.length &&
    common < toParts.length - 1 &&
    fromParts[common] === toParts[common]
  ) {
    common += 1;
  }

  const path = [
    ...Array.from({ length: fromParts.length - common }, () => ".."),
    ...toParts.slice(common),
  ].join("/");

  return path.startsWith(".") ? path : `./${path}`;
}

/** A project-relative path's segments, without `.` and with `..` applied. */
function segments(path: string): string[] {
  const parts: string[] = [];

  for (const part of path.split("/")) {
    if (part === "..") {
      parts.pop();
    } else if (part !== "." && part !== "") {
      parts.push(part);
    }
  }

  return parts;
}
