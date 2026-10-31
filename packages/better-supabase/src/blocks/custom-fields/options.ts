import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.custom-fields.options`. */
export type CustomFieldsSqlOptions = {
  readonly layout?: string;
  /**
   * Writes one `read` audit entry per `read_field_values` call that returns an
   * encrypted or sensitive value. Needs the audit block.
   */
  readonly auditReads?: boolean;
  /**
   * Keyed layout: the type of the `rank` column. `text` (the default) holds
   * fractional keys in `collate "C"` order; `integer` holds whole numbers, cast
   * to the type of the app's own rank column.
   */
  readonly rankType?: "text" | "integer";
  /**
   * Keyed layout: what `read_field_values` checks. `tenant` (the default) needs
   * `permissions.read` in the tenant; `record` needs only that the caller can
   * read the record, through `can_subject(type, id, 'read')`.
   */
  readonly readAccess?: "tenant" | "record";
  /**
   * Field packs (`defineFieldPack`) the app installs per tenant through
   * `customFields.installPacks`. They are plain data, so `gen` carries them to
   * the TypeScript side.
   */
  readonly packs?: readonly unknown[];
  /**
   * Existing `field_definitions.entity` values that aren't registered subject
   * types, mapped to the type that replaces them. Applied once by the 3 to 4
   * upgrade.
   */
  readonly entityMap?: Readonly<Record<string, string>>;
};

export const customFieldsSqlOptions: BlockOptionsSchema<CustomFieldsSqlOptions> =
  blockOptions<CustomFieldsSqlOptions>({
    layout: option.string({ default: "normalized" }),
    auditReads: option.boolean({ default: false }),
    rankType: option.string<"text" | "integer">({ default: "text" }),
    readAccess: option.string<"tenant" | "record">({ default: "tenant" }),
    packs: option.unknown<readonly unknown[]>({ client: true }),
    entityMap: option.extraColumns(),
  });
