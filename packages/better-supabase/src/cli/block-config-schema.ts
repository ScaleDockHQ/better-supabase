import * as v from "valibot";

/**
 * `authorization.versions`: the provider's `(uuid) returns bigint` function,
 * spliced into `caller_authz_version()`, so only a plain `schema.name` passes.
 */
export const authorizationVersionsSchema: v.GenericSchema<{
  function: string;
}> = v.strictObject({
  function: v.pipe(
    v.string(),
    v.regex(
      /^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$/,
      "Use schema.function, e.g. permissions.authz_version_for",
    ),
  ),
});

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
      also?: string | undefined;
      check?: string | undefined;
    }
>;

/**
 * `records.<type>.permissions`: action to a key, or to `{ key, rows, owner,
 * also, check }`. The subject registry checks the names.
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
        also: v.optional(v.string()),
        check: v.optional(v.string()),
      }),
    ]),
  );

type SubjectSearchInput = {
  title?: string | undefined;
  body?: string[] | undefined;
  description?: string | undefined;
  exclude?: string | undefined;
  from?: { view: string; key: string } | undefined;
  watch?:
    | {
        table: string;
        key: string;
        via?: string | undefined;
        through?: { table: string; from: string; to: string }[] | undefined;
      }[]
    | undefined;
};

/** `records.<type>.search`. The subject registry checks the names. */
export const subjectSearchSchema: v.GenericSchema<SubjectSearchInput> =
  v.strictObject({
    title: v.optional(v.string()),
    body: v.optional(v.array(v.string())),
    description: v.optional(v.string()),
    exclude: v.optional(v.string()),
    from: v.optional(v.strictObject({ view: v.string(), key: v.string() })),
    watch: v.optional(
      v.array(
        v.strictObject({
          table: v.string(),
          key: v.string(),
          via: v.optional(v.string()),
          through: v.optional(
            v.array(
              v.strictObject({
                table: v.string(),
                from: v.string(),
                to: v.string(),
              }),
            ),
          ),
        }),
      ),
    ),
  });
