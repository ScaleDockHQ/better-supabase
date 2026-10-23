import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTenantOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireOrganization } from "../../core/block-tenant.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface CustomFieldsOptions extends BlockTenantOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<CustomFields>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface FieldDefinition {
  readonly id: string;
}

export interface FieldDefinitionDetail extends FieldDefinition {
  readonly entity: string;
  readonly key: string;
  readonly label: string;
  /** A `CustomFieldType`, or the value an adopted table stores. */
  readonly type: string;
  readonly required: boolean;
  readonly sensitive: boolean;
  /**
   * Whether values are stored as ciphertext under the tenant's Vault key
   * (`encryptDefinition`). Always `false` without the `field-encryption`
   * block.
   */
  readonly encrypted: boolean;
  /**
   * The rank key, for `reorderDefinition`; absent when definitions aren't
   * ranked.
   */
  readonly rank?: string;
}

/** Every method that takes no definition id acts in the block's `tenant`. */
export interface CustomFields {
  /**
   * One entity's definitions in the tenant, in display order. Needs
   * `custom_fields.read`.
   */
  listDefinitions(entity: string): AsyncResult<FieldDefinitionDetail[]>;
  /** Adds or updates the definition of `key` on `entity`. */
  saveDefinition(
    entity: string,
    key: string,
    label: string,
    type: CustomFieldType,
    sensitive?: boolean,
  ): AsyncResult<FieldDefinition>;
  deleteDefinition(id: string): AsyncResult<boolean>;
  /**
   * Stores a `text`, `email` or `url` field's values as ciphertext from now on
   * and encrypts the ones it has. Needs `custom_fields.manage` and the
   * `field-encryption` block; there is no way back.
   */
  encryptDefinition(id: string): AsyncResult<boolean>;
  /**
   * Moves a definition between the definitions with rank keys `previous` and
   * `next`. Resolves to its new key.
   */
  reorderDefinition(id: string, neighbors: RankNeighbors): AsyncResult<string>;
  /** The custom field values set on `subject`. */
  readValues(subject: RecordRef): AsyncResult<unknown>;
  /** Sets one custom field value of `subject`. */
  setValue(
    subject: RecordRef,
    definitionId: string,
    value: string,
  ): AsyncResult<FieldDefinition>;
}

export function createCustomFields(options: CustomFieldsOptions): CustomFields {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const idOf = (label: string) => (value: unknown) => ({
    id: textOf(recordOf(value, label)["id"]),
  });

  const tenant = (): AsyncResult<string> => requireOrganization(options.tenant);

  const client: CustomFields = {
    listDefinitions: (entity) =>
      tenant().andThen((organizationId) =>
        call(
          "list_field_definitions",
          { tenant: organizationId, entity },
          (value) =>
            recordsOf(value, "list_field_definitions").map((row) => {
              const rank = optionalText(row["rank"]);

              return {
                id: textOf(row["id"]),
                entity: textOf(row["entity"]),
                key: textOf(row["key"]),
                label: textOf(row["label"]),
                type: textOf(row["type"]),
                required: row["required"] === true,
                sensitive: row["sensitive"] === true,
                encrypted: row["encrypted"] === true,
                ...(rank === undefined ? {} : { rank }),
              };
            }),
        ),
      ),
    saveDefinition: (entity, key, label, type, sensitive) =>
      tenant().andThen((organizationId) =>
        call(
          "save_field_definition",
          {
            tenant: organizationId,
            entity,
            key,
            label,
            type,
            sensitive: sensitive ?? false,
          },
          idOf("save_field_definition"),
        ),
      ),
    reorderDefinition: (id, neighbors) => {
      const key = rankBetweenResult(neighbors);

      if (!key.ok) {
        return AsyncResult.err(key.error);
      }

      return call(
        "rank_field_definition",
        { definition: id, rank: key.data },
        () => key.data,
      );
    },
    deleteDefinition: (id) =>
      call(
        "delete_field_definition",
        { definition: id },
        (value) => value === true,
      ),
    encryptDefinition: (id) =>
      call(
        "encrypt_field_definition",
        { definition: id },
        (value) => value === true,
      ),
    readValues: (subject) =>
      tenant().andThen((organizationId) =>
        call(
          "read_field_values",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) => value,
        ),
      ),
    setValue: (subject, definitionId, value) =>
      tenant().andThen((organizationId) =>
        call(
          "set_field_value",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            definition: definitionId,
            value,
          },
          idOf("set_field_value"),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "custom-fields",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
