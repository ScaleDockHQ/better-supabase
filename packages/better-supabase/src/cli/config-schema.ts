import * as v from "valibot";

import type { BetterSupabaseConfig } from "../config/index.ts";

import { providerApiProblem } from "../config/index.ts";
import { SCOPE_ID_TYPES, scopeProblems } from "../sql/index.ts";

const strings = v.array(v.string());
const stringRecord = v.record(v.string(), v.string());
const EXPOSE_PRIVILEGE =
  /^(?:select|insert|update|delete|(?:select|insert|update)\s*\(\s*[a-z_][a-z0-9_$]*(?:\s*,\s*[a-z_][a-z0-9_$]*)*\s*\))$/;
const privileges = v.array(
  v.pipe(
    v.string(),
    v.regex(
      EXPOSE_PRIVILEGE,
      'Use select, insert, update or delete, or name columns such as "update(title, body)"',
    ),
  ),
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
  audit: v.optional(v.boolean()),
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
  model: v.optional(v.picklist(["roles", "catalog", "provider", "custom"])),
  roles: v.optional(v.record(v.string(), strings)),
  functions: v.optional(
    v.strictObject({
      can: v.optional(v.string()),
      tenantIdsWith: v.optional(v.string()),
      isPlatform: v.optional(v.string()),
      canUser: v.optional(v.string()),
      canAssign: v.optional(v.string()),
      canAssignFor: v.optional(v.string()),
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
});

const SCOPE_NAME = /^[a-z][a-z0-9_]*$/;
const scopeName = v.pipe(
  v.string(),
  v.regex(SCOPE_NAME, "Use lower case letters, digits and _"),
);
const membershipScope = v.union([
  v.strictObject({ column: v.string() }),
  v.strictObject({ value: v.string() }),
]);

const authorization = v.strictObject({
  apiVersion: v.literal(1),
  name: v.string(),
  scopes: v.array(
    v.strictObject({
      name: scopeName,
      idType: v.optional(v.picklist(SCOPE_ID_TYPES)),
      parent: v.optional(v.string()),
    }),
  ),
  tenantScope: scopeName,
  functions: v.strictObject({
    idsWith: v.string(),
    isPlatform: v.string(),
    idsWithFor: v.optional(v.string()),
    isPlatformFor: v.optional(v.string()),
    memberIds: v.optional(v.string()),
    memberIdsFor: v.optional(v.string()),
    canAssign: v.optional(v.string()),
    canAssignFor: v.optional(v.string()),
    permissionsFor: v.optional(v.string()),
    canApprove: v.optional(v.string()),
  }),
  requires: v.optional(
    v.array(
      v.strictObject({
        function: v.string(),
        args: v.optional(v.string()),
        role: v.string(),
      }),
    ),
  ),
  permissions: v.optional(
    v.array(
      v.strictObject({
        key: v.string(),
        sqlComplete: v.optional(v.boolean()),
        scopes: v.optional(strings),
      }),
    ),
  ),
  memberships: v.optional(
    v.array(
      v.strictObject({
        table: v.string(),
        userColumn: v.string(),
        scope: membershipScope,
        idColumn: v.string(),
      }),
    ),
  ),
  suspension: v.optional(
    v.strictObject({
      user: v.optional(disabledRow),
      tenant: v.optional(disabledRow),
    }),
  ),
  roleSources: v.optional(
    v.array(
      v.strictObject({
        table: v.string(),
        role: v.strictObject({
          column: v.string(),
          through: v.strictObject({
            table: v.string(),
            id: v.string(),
            column: v.string(),
          }),
        }),
      }),
    ),
  ),
  decidingColumns: v.optional(
    v.array(
      v.pipe(
        v.string(),
        v.regex(
          /^[A-Za-z_][\w$]*\.[A-Za-z_][\w$]*\.[A-Za-z_][\w$]*$/,
          "Use schema.table.column",
        ),
      ),
    ),
  ),
  tokenHook: v.optional(
    v.strictObject({
      function: v.string(),
      tenantClaim: v.optional(v.string()),
      ownedClaims: v.pipe(strings, v.minLength(1, "List at least one claim")),
      registeredClaims: v.optional(
        v.array(v.strictObject({ name: v.string(), function: v.string() })),
      ),
      budget: v.optional(
        v.strictObject({
          claims: strings,
          bytes: v.pipe(
            v.number(),
            v.integer("Use a whole number of bytes"),
            v.minValue(1, "Use at least 1 byte"),
          ),
          truncatedClaim: v.optional(v.string()),
        }),
      ),
      markers: v.optional(
        v.strictObject({
          hook: v.optional(v.string()),
          grants: v.optional(v.string()),
        }),
      ),
      grantsCommand: v.optional(v.string()),
    }),
  ),
  approvals: v.optional(
    v.strictObject({ distinctApprover: v.optional(v.boolean()) }),
  ),
  problems: v.optional(strings),
});

const checkedAuthorization = v.pipe(
  authorization,
  v.rawCheck(({ dataset, addIssue }) => {
    if (!dataset.typed) return;
    for (const problem of scopeProblems(dataset.value)) {
      addIssue({ message: problem });
    }
  }),
);

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
      memberships: v.optional(v.string()),
    }),
  ),
  buckets: v.optional(v.record(v.string(), v.record(v.string(), v.unknown()))),
  topics: v.optional(stringRecord),
  realtime: v.optional(
    v.strictObject({
      tables: v.optional(strings),
      global: v.optional(strings),
      users: v.optional(stringRecord),
      policies: v.optional(
        v.strictObject({ from: strings, output: v.string() }),
      ),
    }),
  ),
  entitlements: v.optional(
    v.strictObject({
      customer: v.optional(v.string()),
      key: v.optional(v.string()),
      memberships: v.optional(v.picklist(["tenant", "provider"])),
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
                value: v.optional(v.string()),
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
  authorization: v.optional(checkedAuthorization),
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
  if (typeof value === "object" && value !== null && "authorization" in value) {
    const provider = value.authorization;
    const problem =
      typeof provider === "object" && provider !== null
        ? providerApiProblem(provider)
        : undefined;
    if (problem !== undefined) {
      const { authorization: _, ...rest } = value;
      return [`authorization.apiVersion: ${problem}`, ...configIssues(rest)];
    }
  }
  const result = v.safeParse(ConfigSchema, value);
  if (result.success) return [];
  return result.issues.map((issue) => {
    const path = v.getDotPath(issue);
    return path ? `${path}: ${issue.message}` : issue.message;
  });
}
