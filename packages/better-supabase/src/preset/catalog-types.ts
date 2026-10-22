import type { BlockCategory } from "../blocks/define-block.ts";
import type { PortName } from "../blocks/ports.ts";
import type { FieldSpec } from "../core/table-json-schema.ts";
import type { ModuleEntitySpec, ModuleTableSpec } from "../sql/context.ts";
import type { PresetAccess, PresetScope, PresetTenantName } from "./fields.ts";

/** One SQL module in the preset catalog: a key of `blocks` in the config. */
export interface PresetCatalogBlock {
  readonly name: string;
  readonly title: string;
  readonly category: BlockCategory;
  /** The modules it needs with the default options. */
  readonly requires: readonly string[];
  /** What it needs instead under an access model, where that differs. */
  readonly requiresByAccess?: Partial<
    Readonly<Record<PresetAccess, readonly string[]>>
  >;
  /** The scopes it runs in; unset, every scope. */
  readonly scopes?: readonly PresetScope[];
  /** Tenant names that would rename a table or column to a name it already uses. */
  readonly tenantNameClashes?: readonly PresetTenantName[];
  /**
   * The logical table `options.extraColumns` adds columns to, when it takes
   * them.
   */
  readonly extraColumns?: string;
  /**
   * The nouns `blocks.<name>.entities` renames, with what config resolution
   * needs to name them and register their subjects.
   */
  readonly entities?: PresetCatalogEntities;
  /** Modules it works with when installed; `*` is every module. */
  readonly integrates: readonly string[];
  /** The manifest that installs it, a key of `manifests`. */
  readonly manifest: string;
}

/** A block's entities as the catalog carries them. */
export interface PresetCatalogEntities {
  readonly specs: Readonly<Record<string, ModuleEntitySpec>>;
  /** The tables that hold them, with their default names and columns. */
  readonly tables: Readonly<
    Record<string, Pick<ModuleTableSpec, "name" | "columns">>
  >;
  /** The default permission key of each module action. */
  readonly keys: Readonly<Record<string, string>>;
}

/** One block manifest (ADR 0029): what `lib/blocks.ts` wires. */
export interface PresetCatalogManifest {
  readonly name: string;
  /** The SQL modules it installs. */
  readonly sql: readonly string[];
  readonly category: BlockCategory;
  /** Its export and subpath, when it has a TypeScript client. */
  readonly client: { readonly export: string; readonly subpath: string } | null;
  readonly consumes: Partial<
    Readonly<Record<PortName, "optional" | "required">>
  >;
  readonly provides: readonly PortName[];
  /**
   * The types its subpath exports that carry one of its entities' names, which
   * `gen` aliases under the renamed names.
   */
  readonly entityTypes?: readonly PresetCatalogEntityType[];
  /**
   * JSON Schemas of the inputs its client takes, by entity key, from the
   * Standard Schemas the block exports.
   */
  readonly entitySchemas?: Readonly<Record<string, PresetCatalogEntitySchemas>>;
  /**
   * The block's events: the event map type its subpath exports and the event
   * types, in its default names.
   */
  readonly events?: {
    readonly type: string;
    readonly types: readonly string[];
  };
  /**
   * The record sections its client adds (`block.sections`) with each one's
   * write names, which `gen` puts on each subject's record feature.
   */
  readonly sections?: Readonly<Record<string, readonly string[]>>;
}

/** One entity's input schemas, in the block's default names. */
export interface PresetCatalogEntitySchemas {
  readonly input?: PresetCatalogInputSchema;
  readonly change?: PresetCatalogInputSchema;
  readonly listFilter?: PresetCatalogInputSchema;
}

/** One input schema: its fields as `entitySchema` takes them, and JSON Schema. */
export interface PresetCatalogInputSchema {
  readonly title: string;
  readonly fields: Readonly<Record<string, FieldSpec>>;
  readonly jsonSchema: Readonly<Record<string, unknown>>;
}

/** A block type named after one of its entities, such as `WorkItem`. */
export interface PresetCatalogEntityType {
  readonly name: string;
  /** Takes the extra columns as its first type parameter, `F`. */
  readonly fields?: true;
}

/**
 * One item of the `@better-supabase` shadcn registry: glue the app copies (`npx
 * shadcn add @better-supabase/<name>`), for some blocks, frameworks and
 * platforms.
 */
export interface PresetGlueItem {
  readonly name: string;
  readonly title: string;
  /** The SQL modules the item needs. */
  readonly blocks: readonly string[];
  readonly frameworks: readonly string[];
  readonly platforms: readonly ("web" | "native")[];
  /** Where its files go, as shadcn targets (`@lib/blocks.ts`, `~/app/...`). */
  readonly targets: readonly string[];
  /** The named preset a bundle item (`registry:item`) installs the glue of. */
  readonly preset?: string;
}

/** What `scripts/build-catalog.ts` writes to `catalog.generated.ts`. */
export interface PresetCatalog {
  readonly blocks: readonly PresetCatalogBlock[];
  readonly manifests: readonly PresetCatalogManifest[];
  readonly glue: readonly PresetGlueItem[];
}
