import * as v from "valibot";

interface EntityPageInput {
  apiVersion: 1;
  entity: string;
  route: string;
  name?: string | undefined;
  reads?: string | undefined;
  methods?:
    | { page?: string | undefined; facets?: string | undefined }
    | undefined;
  list?:
    | { pageSize?: number | undefined; maxPageSize?: number | undefined }
    | undefined;
  area?: string | undefined;
  columns?: string[] | undefined;
  sections?: string[] | undefined;
  seed?:
    | { demo?: number | undefined; tiers?: string[] | undefined }
    | undefined;
  export?:
    | {
        filename?: string | undefined;
        columns?: string[] | undefined;
        maxRows?: number | undefined;
      }
    | undefined;
}

const positive = v.pipe(v.number(), v.integer(), v.minValue(1));

/**
 * One `defineEntityPage` descriptor in `gen.entityPages.pages`. It names every
 * field the generators read, so a later lane adds its output without a new
 * config key.
 */
export const entityPageSchema: v.GenericSchema<EntityPageInput> =
  v.strictObject({
    apiVersion: v.literal(1),
    entity: v.pipe(
      v.string(),
      v.regex(
        /^[a-z][a-z0-9-]*\.[a-z][a-z0-9_]*$/,
        'must be "<block>.<entity>", such as "risks.risk"',
      ),
    ),
    route: v.pipe(v.string(), v.startsWith("/")),
    name: v.optional(v.pipe(v.string(), v.regex(/^[a-z][a-z0-9-]*$/))),
    reads: v.optional(v.string()),
    methods: v.optional(
      v.strictObject({
        page: v.optional(v.pipe(v.string(), v.regex(/^[A-Za-z_$][\w$]*$/))),
        facets: v.optional(v.pipe(v.string(), v.regex(/^[A-Za-z_$][\w$]*$/))),
      }),
    ),
    list: v.optional(
      v.strictObject({
        pageSize: v.optional(positive),
        maxPageSize: v.optional(positive),
      }),
    ),
    area: v.optional(v.string()),
    columns: v.optional(v.array(v.string())),
    sections: v.optional(v.array(v.string())),
    seed: v.optional(
      v.strictObject({
        demo: v.optional(positive),
        tiers: v.optional(v.array(v.string())),
      }),
    ),
    export: v.optional(
      v.strictObject({
        filename: v.optional(v.string()),
        columns: v.optional(v.array(v.string())),
        maxRows: v.optional(positive),
      }),
    ),
  });
