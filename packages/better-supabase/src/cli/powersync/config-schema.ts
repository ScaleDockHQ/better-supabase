import * as v from "valibot";

interface PowerSyncGenInput {
  instances: string[];
  out?: string | undefined;
  import?: string | undefined;
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
  });
