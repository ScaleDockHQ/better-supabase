import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface CustomFieldsOptions {
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
  /** The rank key, for `reorderDefinition`; absent when definitions aren't ranked. */
  readonly rank?: string;
}

export interface CustomFields {
  /** One entity's definitions in display order. Needs `custom_fields.read`. */
  listDefinitions(
    organizationId: string,
    entity: string,
  ): AsyncResult<FieldDefinitionDetail[]>;
  saveDefinition(
    organizationId: string,
    entity: string,
    key: string,
    label: string,
    type: CustomFieldType,
    sensitive?: boolean,
  ): AsyncResult<FieldDefinition>;
  deleteDefinition(id: string): AsyncResult<boolean>;
  /**
   * Moves a definition between the definitions with rank keys `previous`
   * and `next`. Resolves to its new key.
   */
  reorderDefinition(id: string, neighbors: RankNeighbors): AsyncResult<string>;
  readValues(
    organizationId: string,
    subjectType: string,
    subjectId: string,
  ): AsyncResult<unknown>;
  setValue(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    definitionId: string,
    value: string,
  ): AsyncResult<FieldDefinition>;
}

export function createCustomFields(options: CustomFieldsOptions): CustomFields {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const idOf = (label: string) => (value: unknown) => ({
    id: textOf(recordOf(value, label)["id"]),
  });

  const client: CustomFields = {
    listDefinitions: (organizationId, entity) =>
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
              ...(rank === undefined ? {} : { rank }),
            };
          }),
      ),
    saveDefinition: (organizationId, entity, key, label, type, sensitive) =>
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
    readValues: (organizationId, subjectType, subjectId) =>
      call(
        "read_field_values",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
        },
        (value) => value,
      ),
    setValue: (organizationId, subjectType, subjectId, definitionId, value) =>
      call(
        "set_field_value",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          definition: definitionId,
          value,
        },
        idOf("set_field_value"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "custom-fields",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
