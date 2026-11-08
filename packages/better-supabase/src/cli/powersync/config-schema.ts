import * as v from "valibot";

interface PowerSyncGenInput {
  instances: string[];
  out?: string | undefined;
  import?: string | undefined;
  children?: { table: string; parent: string; column: string }[] | undefined;
}

/** `gen.powersync`. */
export const powersyncGenSchema: v.GenericSchema<PowerSyncGenInput> =
  v.strictObject({
    instances: v.pipe(
      v.array(v.string()),
      v.minLength(1, "lists at least one block instance"),
    ),
    out: v.optional(v.string()),
    import: v.optional(v.string()),
    children: v.optional(
      v.array(
        v.strictObject({
          table: v.pipe(
            v.string(),
            v.regex(/^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/, "is schema.table"),
          ),
          parent: v.string(),
          column: v.string(),
        }),
      ),
    ),
  });
