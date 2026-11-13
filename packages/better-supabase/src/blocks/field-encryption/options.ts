import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * Columns the app's own SQL seals with the block's keys (its own trigger
 * calling `field_seal`), so `rotate_field_key` encrypts them again and
 * `field_key_status` lists them. App tables in `tables` with `encrypted`
 * columns and encrypted custom fields are found without it.
 */
export interface SealedColumns {
  /** `schema.table`, such as `public.client_notes`. */
  readonly table: string;
  readonly columns: readonly string[];
  /** Whose key seals a row: its tenant's, its user's or the app's. */
  readonly owner: "tenant" | "user" | "app";
  /**
   * The column that holds the row's tenant or user. Default `organization_id`
   * (as renamed) for a tenant, `user_id` for a user.
   */
  readonly column?: string;
}

/** `blocks.field-encryption.options`. */
export type FieldEncryptionSqlOptions = {
  readonly sealed?: readonly SealedColumns[];
};

export const fieldEncryptionSqlOptions: BlockOptionsSchema<FieldEncryptionSqlOptions> =
  blockOptions<FieldEncryptionSqlOptions>({
    sealed: option.unknown<readonly SealedColumns[]>(),
  });
