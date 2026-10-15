import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.settings.options`. */
export type SettingsSqlOptions = {
  readonly schemas?: unknown;
  readonly platform?: unknown;
};

export const settingsSqlOptions: BlockOptionsSchema<SettingsSqlOptions> =
  blockOptions<SettingsSqlOptions>({
    schemas: option.unknown(),
    platform: option.unknown(),
  });
