import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type { EntitySchema } from "../entity-schema.ts";
import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type {
  CustomFields,
  FieldValue,
  SetFieldInput,
} from "./custom-fields.ts";

import { AsyncResult, ok } from "../../core/result.ts";
import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding } from "../record-bindings.ts";

/** The input schema of the custom-fields binding's `set`. */
export const setFieldInput: EntitySchema<SetFieldInput> =
  entitySchema<SetFieldInput>({
    title: "SetFieldInput",
    fields: {
      key: { kind: "string", minLength: 1 },
      label: { kind: "string", minLength: 1 },
      type: { kind: "string", minLength: 1 },
      value: { kind: "json" },
      rank: { kind: "string", optional: true, minLength: 1 },
      ifAbsent: { kind: "boolean", optional: true },
    },
  });

/** The writes of the custom-fields binding. */
export type CustomFieldsWrites = {
  /** Sets one field value on the record (keyed layout). */
  readonly set: RecordBindingWrite<CustomFields, SetFieldInput, FieldValue>;
};

/** A record's custom field values (keyed layout). */
export const customFieldsBinding: RecordBinding<
  CustomFields,
  FieldValue[],
  never,
  never,
  CustomFieldsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "custom-fields",
  load: (client: CustomFields, subject) => client.readFields(subject),
  copy: (client: CustomFields, from, to) =>
    client.readFields(from).andThen((values) =>
      AsyncResult.from(async () => {
        for (const value of values) {
          const copied = await client.setField({
            subject: to,
            input: {
              key: value.key,
              label: value.label,
              // SAFETY: the type comes from a value this block stored.
              type: value.type as CustomFieldType,
              value: value.value,
            },
          });

          if (!copied.ok) {
            return copied;
          }
        }

        return ok(values.length);
      }),
    ),
  events: ["field_value.*"],
  writes: {
    set: {
      input: setFieldInput,
      run: (client: CustomFields, subject, input: SetFieldInput) =>
        client.setField({ subject, input }),
    },
  },
});
