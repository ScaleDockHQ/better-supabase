import { resolveConfig } from "better-supabase/config";
import { type Preset, presetOf } from "better-supabase/preset";
import {
  type ModuleAccessProvider,
  moduleLayout,
  renderModules,
} from "better-supabase/sql";

import type { PresetMigrationFile } from "./create";

/**
 * A stand-in for the app's authorization provider, so `/create` can render
 * the SQL and the diagram for `access: "provider"`. Its templates call
 * functions in a `provider` schema that no real project has: the preview
 * says so next to the output.
 */
export function previewAccessProvider(preset: Preset): ModuleAccessProvider {
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
 * The files `sql sync` writes for a config with only this preset. With
 * `access: "provider"` the access functions come from
 * `previewAccessProvider`.
 */
export function previewFiles(code: string): readonly PresetMigrationFile[] {
  const preset = presetOf(code);
  const config = resolveConfig({ preset: code }, "/");

  const provider =
    preset.access === "provider" ? previewAccessProvider(preset) : undefined;

  return renderModules(
    config.blockNames,
    moduleLayout(config, config.sql.testsDir, [], undefined, provider),
  ).map((file) => ({
    path: file.path,
    module: file.module,
    contents: file.contents,
  }));
}
