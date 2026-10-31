import * as v from "valibot";

interface BucketPolicyInput {
  access: {
    read: string;
    list?: string | undefined;
    write: string;
    delete?: string | undefined;
  };
  scope?: string | undefined;
  segment?: number | undefined;
  sql?: "provider" | { idsWith: string; isPlatform: string } | undefined;
}

interface BucketLifecycleRuleInput {
  id?: string | undefined;
  status?: "Enabled" | "Disabled" | undefined;
  noncurrentVersionExpiration: {
    noncurrentDays: number;
    newerNoncurrentVersions?: number | undefined;
  };
}

interface BucketInput {
  id?: string | undefined;
  public?: boolean | undefined;
  path: string | string[];
  policy?:
    | "tenant"
    | "owner"
    | "public"
    | "none"
    | BucketPolicyInput
    | undefined;
  fileSizeLimit?: string | undefined;
  allowedMimeTypes?: string[] | undefined;
  versioning?: boolean | undefined;
  lifecycle?: { rules: BucketLifecycleRuleInput[] } | undefined;
}

const positiveInteger = v.pipe(v.number(), v.integer(), v.minValue(1));

/** `buckets.<name>`: a Storage bucket, its policy and its lifecycle rules. */
export const bucketSchema: v.GenericSchema<BucketInput> = v.strictObject({
  id: v.optional(v.string()),
  public: v.optional(v.boolean()),
  path: v.union([v.string(), v.pipe(v.array(v.string()), v.minLength(1))]),
  policy: v.optional(
    v.union([
      v.picklist(["tenant", "owner", "public", "none"]),
      v.strictObject({
        access: v.strictObject({
          read: v.string(),
          list: v.optional(v.string()),
          write: v.string(),
          delete: v.optional(v.string()),
        }),
        scope: v.optional(v.string()),
        segment: v.optional(positiveInteger),
        sql: v.optional(
          v.union([
            v.literal("provider"),
            v.strictObject({ idsWith: v.string(), isPlatform: v.string() }),
          ]),
        ),
      }),
    ]),
  ),
  fileSizeLimit: v.optional(v.string()),
  allowedMimeTypes: v.optional(v.array(v.string())),
  versioning: v.optional(v.boolean()),
  lifecycle: v.optional(
    v.strictObject({
      rules: v.pipe(
        v.array(
          v.strictObject({
            id: v.optional(v.string()),
            status: v.optional(v.picklist(["Enabled", "Disabled"])),
            noncurrentVersionExpiration: v.strictObject({
              noncurrentDays: positiveInteger,
              newerNoncurrentVersions: v.optional(
                v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(100)),
              ),
            }),
          }),
        ),
        v.minLength(1),
        v.maxLength(1000),
      ),
    }),
  ),
});
