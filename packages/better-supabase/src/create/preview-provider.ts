import type { CreateDesign, Preset } from "../preset/index.ts";
import type { BlockSqlAccessProvider } from "../sql/index.ts";
import type { PresetMigrationFile } from "./types.ts";

import { resolveConfig } from "../config/index.ts";
import { designConfig, presetOf, resolvePreset } from "../preset/index.ts";
import { moduleLayout, renderBlocks } from "../sql/index.ts";

/**
 * A stand-in for the app's authorization provider, so `/create` can render the
 * SQL and the diagram for `access: "provider"`. Its templates call functions in
 * a `provider` schema that no real project has: the preview says so next to the
 * output.
 */
export function previewAccessProvider(preset: Preset): BlockSqlAccessProvider {
  return {
    name: "your authorization provider",
    scope: preset.tenantName,
    idType: preset.idType,
    functions: {
      idsWith: "provider.ids_with('{scope}', {permission})",
      idsWithFor: "provider.ids_with_for({user}, '{scope}', {permission})",
      isPlatform: "provider.is_platform({permission})",
      isPlatformFor: "provider.is_platform_for({user}, {permission})",
      memberIds: "provider.member_ids('{scope}')",
      memberIdsFor: "provider.member_ids_for({user}, '{scope}')",
    },
  };
}

/**
 * The files `upgrade` writes for a config with only this preset and its
 * `/create` design (app tables and extra columns). With `access: "provider"`
 * the access functions come from `previewAccessProvider`.
 */
export function previewFiles(
  code: string,
  design: CreateDesign = {},
): readonly PresetMigrationFile[] {
  const preset = presetOf(code);

  const config = resolveConfig(
    Object.keys(design).length === 0
      ? { preset: code }
      : designConfig(resolvePreset(preset), design),
    "/",
  );

  const provider =
    preset.access === "provider" ? previewAccessProvider(preset) : undefined;

  return renderBlocks(
    config.blockNames,
    moduleLayout(config, config.sql.testsDir, [], undefined, provider),
  ).map((file) => ({
    path: file.path,
    module: file.module,
    contents: file.contents,
  }));
}
