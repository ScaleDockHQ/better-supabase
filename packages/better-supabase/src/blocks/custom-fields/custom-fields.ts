import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall, recordOf, textOf } from "../shared.ts";

export interface CustomFieldsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface FieldDefinition {
  readonly id: string;
}

export interface CustomFields {
  saveDefinition(
    organizationId: string,
    entity: string,
    key: string,
    label: string,
    type: string,
    sensitive?: boolean,
  ): AsyncResult<FieldDefinition>;
  deleteDefinition(id: string): AsyncResult<boolean>;
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
  return {
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
}
