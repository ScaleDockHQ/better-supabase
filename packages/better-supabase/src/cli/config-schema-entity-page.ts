import * as v from "valibot";

type SeedValue = string | number | boolean | null;

interface EntityPageInput {
  apiVersion: 1;
  entity: string;
  route: string;
  name?: string | undefined;
  reads?: string | undefined;
  tenantOption?: string | undefined;
  app?:
    | {
        surface: {
          sorts?: string[] | undefined;
          facets?: string[] | undefined;
          filters?: string[] | undefined;
          search?: boolean | string[] | undefined;
        };
        table?:
          | {
              schema?: string | undefined;
              name: string;
              tenant?: string | undefined;
              columns: Record<string, string>;
            }
          | undefined;
        reads: { module: string; export: string };
        blocks?: string[] | undefined;
      }
    | undefined;
  methods?:
    | { page?: string | undefined; facets?: string | undefined }
    | undefined;
  sortLists?: string[][] | undefined;
  list?:
    | { pageSize?: number | undefined; maxPageSize?: number | undefined }
    | undefined;
  area?: string | undefined;
  columns?: string[] | undefined;
  sections?: string[] | undefined;
  seed?:
    | {
        demo?: number | undefined;
        tiers?: string[] | undefined;
        fields?: Record<string, SeedValue | SeedValue[]> | undefined;
        rows?: Record<string, SeedValue>[] | undefined;
        table?: string | undefined;
        tenant?: string | undefined;
      }
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

const seedValue = v.union([v.string(), v.number(), v.boolean(), v.null()]);

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
    tenantOption: v.optional(v.pipe(v.string(), v.regex(/^[A-Za-z_$][\w$]*$/))),
    app: v.optional(
      v.strictObject({
        surface: v.strictObject({
          sorts: v.optional(v.array(v.string())),
          facets: v.optional(v.array(v.string())),
          filters: v.optional(v.array(v.string())),
          search: v.optional(v.union([v.boolean(), v.array(v.string())])),
        }),
        table: v.optional(
          v.strictObject({
            schema: v.optional(v.string()),
            name: v.string(),
            tenant: v.optional(v.string()),
            columns: v.record(v.string(), v.string()),
          }),
        ),
        reads: v.strictObject({ module: v.string(), export: v.string() }),
        blocks: v.optional(v.array(v.string())),
      }),
    ),
    methods: v.optional(
      v.strictObject({
        page: v.optional(v.pipe(v.string(), v.regex(/^[A-Za-z_$][\w$]*$/))),
        facets: v.optional(v.pipe(v.string(), v.regex(/^[A-Za-z_$][\w$]*$/))),
      }),
    ),
    sortLists: v.optional(v.array(v.array(v.string()))),
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
        fields: v.optional(
          v.record(v.string(), v.union([seedValue, v.array(seedValue)])),
        ),
        rows: v.optional(v.array(v.record(v.string(), seedValue))),
        table: v.optional(v.string()),
        tenant: v.optional(v.string()),
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
