import * as v from "valibot";

import type { BetterSupabaseConfig } from "../config/index.ts";

const strings = v.array(v.string());
const stringRecord = v.record(v.string(), v.string());
const privileges = v.array(
  v.picklist(["select", "insert", "update", "delete"]),
);
const pluginFlag = v.union([v.boolean(), v.record(v.string(), v.unknown())]);

const isGenerator = (value: unknown): boolean =>
  typeof value === "object" &&
  value !== null &&
  "name" in value &&
  typeof value.name === "string" &&
  "generate" in value &&
  typeof value.generate === "function";

/**
 * The top level of `better-supabase.config.*`. It rejects unknown keys and
 * checks the leaves a typo or an old value breaks; nested objects the
 * library reads loosely stay loose.
 */
const moduleEntries = {
  mode: v.optional(v.picklist(["managed", "adopt", "custom"])),
  schema: v.optional(v.string()),
  tables: v.optional(v.record(v.string(), v.nullable(v.string()))),
  columns: v.optional(
    v.record(v.string(), v.record(v.string(), v.nullable(v.string()))),
  ),
  idType: v.optional(v.string()),
  permissions: v.optional(stringRecord),
  options: v.optional(v.record(v.string(), v.unknown())),
  hooks: v.optional(
    v.strictObject({
      schema: v.optional(v.string()),
      functions: v.optional(stringRecord),
    }),
  ),
  events: v.optional(v.boolean()),
  api: v.optional(
    v.union([
      v.string(),
      v.strictObject({
        schema: v.string(),
        functions: v.optional(strings),
      }),
    ]),
  ),
};

const disabledRow = v.strictObject({
  table: v.string(),
  id: v.string(),
  disabledAt: v.optional(v.string()),
  status: v.optional(v.string()),
  active: v.optional(strings),
});

const accessModule = v.strictObject({
  ...moduleEntries,
  model: v.optional(v.picklist(["roles", "catalog", "permdock", "custom"])),
  roles: v.optional(v.record(v.string(), strings)),
  functions: v.optional(
    v.strictObject({
      can: v.optional(v.string()),
      tenantIdsWith: v.optional(v.string()),
      isPlatform: v.optional(v.string()),
      canUser: v.optional(v.string()),
      canAssign: v.optional(v.string()),
      permissionClaims: v.optional(v.string()),
    }),
  ),
  platformClaim: v.optional(v.string()),
  disabled: v.optional(
    v.strictObject({
      tenant: v.optional(v.union([v.string(), disabledRow])),
      user: v.optional(v.union([v.string(), disabledRow])),
      userKey: v.optional(v.string()),
    }),
  ),
  activeTenant: v.optional(
    v.union([
      v.picklist(["claim", "resolver"]),
      v.strictObject({
        profileColumn: v.string(),
        key: v.optional(v.string()),
      }),
    ]),
  ),
  permdock: v.optional(
    v.strictObject({
      schema: v.optional(v.string()),
      scope: v.optional(v.string()),
      forUser: v.optional(v.boolean()),
    }),
  ),
});

const ConfigSchema = v.strictObject({
  $schema: v.optional(v.string()),
  source: v.optional(
    v.strictObject({
      dbUrl: v.optional(v.string()),
      projectRef: v.optional(v.string()),
      accessToken: v.optional(v.string()),
      snapshot: v.optional(v.string()),
    }),
  ),
  schemas: v.optional(strings),
  casing: v.optional(v.picklist(["snake", "camel"])),
  tables: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        casing: v.optional(v.picklist(["snake", "camel"])),
        exclude: v.optional(v.boolean()),
        serviceRole: v.optional(v.boolean()),
        relations: v.optional(stringRecord),
        insertOptional: v.optional(strings),
      }),
    ),
  ),
  output: v.optional(v.string()),
  postgrestVersion: v.optional(v.string()),
  json: v.optional(v.record(v.string(), v.unknown())),
  codecs: v.optional(
    v.strictObject({
      timestamptz: v.optional(v.picklist(["string", "instant"])),
      int8: v.optional(v.picklist(["number", "string", "bigint"])),
      numeric: v.optional(v.picklist(["number", "string"])),
    }),
  ),
  relations: v.optional(
    v.strictObject({ nullableUnderRls: v.optional(v.boolean()) }),
  ),
  sensitive: v.optional(strings),
  storagePaths: v.optional(stringRecord),
  functions: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        notNull: v.optional(v.union([v.literal(true), strings])),
      }),
    ),
  ),
  expose: v.optional(
    v.record(
      v.string(),
      v.union([
        privileges,
        v.strictObject({
          anon: v.optional(privileges),
          authenticated: v.optional(privileges),
          serviceRole: v.optional(privileges),
        }),
        v.strictObject({
          execute: v.array(v.picklist(["anon", "authenticated"])),
          serviceRole: v.optional(v.boolean()),
        }),
      ]),
    ),
  ),
  readSets: v.optional(strings),
  generators: v.optional(
    v.array(
      v.custom(isGenerator, "must be a generator: { name, generate(input) }"),
    ),
  ),
  plugins: v.optional(
    v.strictObject({
      timestamps: v.optional(pluginFlag),
      softDelete: v.optional(pluginFlag),
      tenant: v.optional(pluginFlag),
      actor: v.optional(pluginFlag),
    }),
  ),
  claims: v.optional(
    v.strictObject({
      tenant: v.optional(v.string()),
      scope: v.optional(v.string()),
      features: v.optional(v.string()),
    }),
  ),
  buckets: v.optional(v.record(v.string(), v.record(v.string(), v.unknown()))),
  topics: v.optional(stringRecord),
  realtime: v.optional(
    v.strictObject({
      tables: v.optional(strings),
      global: v.optional(strings),
      policies: v.optional(
        v.strictObject({ from: strings, output: v.string() }),
      ),
    }),
  ),
  entitlements: v.optional(
    v.strictObject({
      customer: v.optional(v.string()),
      key: v.optional(v.string()),
      permdock: v.optional(
        v.union([
          v.literal(false),
          v.strictObject({ scope: v.optional(v.string()) }),
        ]),
      ),
      source: v.optional(
        v.union([
          v.picklist(["stripe-sync", "custom"]),
          v.strictObject({
            plans: v.strictObject({
              subscriptions: v.strictObject({
                table: v.string(),
                tenant: v.string(),
                plan: v.string(),
                status: v.optional(v.string()),
                activeStatuses: v.optional(strings),
              }),
              features: v.strictObject({
                table: v.string(),
                plan: v.string(),
                feature: v.string(),
                included: v.optional(v.string()),
              }),
            }),
          }),
        ]),
      ),
      claim: v.optional(
        v.union([
          v.literal(false),
          v.strictObject({
            maxTenants: v.optional(v.number()),
            keys: v.optional(stringRecord),
          }),
        ]),
      ),
    }),
  ),
  permdock: v.optional(
    v.strictObject({
      manifest: v.optional(v.string()),
      catalog: v.optional(v.string()),
    }),
  ),
  vectorSearch: v.optional(
    v.record(
      v.string(),
      v.union([
        v.string(),
        v.strictObject({
          column: v.string(),
          distance: v.optional(v.picklist(["cosine", "l2", "inner_product"])),
          type: v.optional(v.picklist(["vector", "halfvec"])),
          key: v.optional(v.string()),
          hybrid: v.optional(
            v.strictObject({
              tsvector: v.string(),
              config: v.optional(v.string()),
              k: v.optional(v.number()),
            }),
          ),
          boost: v.optional(v.string()),
          prefilter: v.optional(strings),
          predicate: v.optional(v.string()),
          boostMode: v.optional(v.picklist(["multiply", "add"])),
          order: v.optional(v.string()),
        }),
      ]),
    ),
  ),
  sql: v.optional(
    v.strictObject({
      dir: v.optional(v.string()),
      prefix: v.optional(v.string()),
      testsDir: v.optional(v.string()),
      modules: v.optional(
        v.lazy((input) =>
          Array.isArray(input)
            ? strings
            : v.objectWithRest(
                { access: v.optional(accessModule) },
                v.strictObject(moduleEntries),
              ),
        ),
      ),
    }),
  ),
  seed: v.optional(
    v.strictObject({
      entry: v.optional(v.string()),
      output: v.optional(v.string()),
    }),
  ),
  openapi: v.optional(
    v.strictObject({
      entry: v.optional(v.string()),
      output: v.optional(v.string()),
    }),
  ),
  doctor: v.optional(
    v.strictObject({
      ignore: v.optional(strings),
      strict: v.optional(v.boolean()),
      sources: v.optional(strings),
      policyHelperLimit: v.optional(v.number()),
      claimsLimit: v.optional(v.number()),
    }),
  ),
} satisfies { [K in keyof Required<BetterSupabaseConfig>]: v.GenericSchema });

/** Each issue as `path: message`, the path in config keys. */
export function configIssues(value: unknown): string[] {
  const result = v.safeParse(ConfigSchema, value);
  if (result.success) return [];
  return result.issues.map((issue) => {
    const path = v.getDotPath(issue);
    return path ? `${path}: ${issue.message}` : issue.message;
  });
}
