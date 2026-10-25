import * as v from "valibot";

type ValueMapsInput = Record<
  string,
  Record<string, Record<string, string | string[] | null>>
>;

/**
 * `blocks.<name>.values`: table to column to label to an app value, a list of
 * app values, or `null`. The module context checks the names.
 */
export const valueMapsSchema: v.GenericSchema<ValueMapsInput> = v.record(
  v.string(),
  v.record(
    v.string(),
    v.record(
      v.string(),
      v.nullable(v.union([v.string(), v.array(v.string())])),
    ),
  ),
);

type SubjectPermissionsInput = Record<
  string,
  | string
  | {
      key?: string | undefined;
      rows?: string | undefined;
      owner?: string | undefined;
    }
>;

/**
 * `records.<type>.permissions`: action to a key, or to `{ key, rows, owner }`.
 * The subject registry checks the names.
 */
export const subjectPermissionsSchema: v.GenericSchema<SubjectPermissionsInput> =
  v.record(
    v.string(),
    v.union([
      v.string(),
      v.strictObject({
        key: v.optional(v.string()),
        rows: v.optional(v.string()),
        owner: v.optional(v.string()),
      }),
    ]),
  );
