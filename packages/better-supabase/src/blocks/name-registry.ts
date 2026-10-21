import type { BlockNameRegistry } from "./name-registry.generated.ts";

export type { BlockNameRegistry };

/** The names one module's config keys accept. */
export interface ModuleNameSet {
  /** Logical table to its logical columns. */
  readonly tables: { readonly [table: string]: string };
  readonly functions: string;
  readonly actions: string;
  readonly hooks: string;
  /** Entity to the default column names of its table. */
  readonly entities: { readonly [entity: string]: string };
  readonly primary: string;
}

/** The names of a module the registry doesn't know: every name is a string. */
export type AnyModuleNames = ModuleNameSet;

export type NamesOf<M extends string> = M extends keyof BlockNameRegistry
  ? BlockNameRegistry[M]
  : AnyModuleNames;

export type TablesOf<M extends string> = keyof NamesOf<M>["tables"] & string;

export type ColumnsOf<
  M extends string,
  T extends TablesOf<M>,
> = NamesOf<M>["tables"][T];

export type FunctionsOf<M extends string> = NamesOf<M>["functions"];

export type ActionsOf<M extends string> = NamesOf<M>["actions"];

export type HooksOf<M extends string> = NamesOf<M>["hooks"];

export type EntitiesOf<M extends string> = keyof NamesOf<M>["entities"] &
  string;
