import type { BlockCategory } from "../blocks/define-block.ts";
import type { PortName } from "../blocks/ports.ts";
import type { PresetAccess } from "./fields.ts";

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
  /** Modules it works with when installed; `*` is every module. */
  readonly integrates: readonly string[];
  /** The manifest that installs it, a key of `manifests`. */
  readonly manifest: string;
}

/** One block manifest (ADR 0029): what `lib/blocks.ts` wires. */
export interface PresetCatalogManifest {
  readonly name: string;
  /** The SQL modules it installs. */
  readonly sql: readonly string[];
  readonly category: BlockCategory;
  /** Its export and subpath, when it has a TypeScript client. */
  readonly client: {
    readonly export: string;
    readonly subpath: string;
  } | null;
  readonly consumes: Partial<
    Readonly<Record<PortName, "optional" | "required">>
  >;
  readonly provides: readonly PortName[];
}

/** What `scripts/build-catalog.ts` writes to `catalog.generated.ts`. */
export interface PresetCatalog {
  readonly blocks: readonly PresetCatalogBlock[];
  readonly manifests: readonly PresetCatalogManifest[];
}
