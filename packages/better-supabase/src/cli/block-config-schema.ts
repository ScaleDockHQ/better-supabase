import * as v from "valibot";

/**
 * `blocks.<name>.values`: table to column to label to an app value, a list of
 * app values, or `null`. The module context checks the names.
 */
type ValueMapsInput =
  | Record<string, Record<string, Record<string, string | string[] | null>>>
  | undefined;

export const valueMapsSchema: v.GenericSchema<ValueMapsInput> = v.optional(
  v.record(
    v.string(),
    v.record(
      v.string(),
      v.record(
        v.string(),
        v.nullable(v.union([v.string(), v.array(v.string())])),
      ),
    ),
  ),
);
