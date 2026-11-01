import * as v from "valibot";

import type {
  BetterSupabaseConfig,
  BlocksConfig,
  EnvironmentConfig,
  ExposePrivilege,
  Generator,
  TopicTriggerValueConfig,
} from "../config/index.ts";
import type { ParityPaths } from "./type-parity.ts";

import {
  APP_COLUMN_ACCESS,
  APP_COLUMN_FORMATS,
  APP_COLUMN_TYPES,
  APP_ON_DELETE_ACTIONS,
  APP_ROLLUP_AGGREGATES,
  APP_TABLE_EVENT_KINDS,
  providerApiProblem,
  SKILLS_AGENTS,
} from "../config/index.ts";
import { CONVENTION_FIELDS } from "../preset/index.ts";
import { SCOPE_ID_TYPES, scopeProblems } from "../sql/index.ts";
import * as blockSchemas from "./block-config-schema.ts";
import { movedKeyIssues } from "./config-moved.ts";
import { bucketSchema } from "./config-schema-bucket.ts";
import { hooksSchema, sourceSchema } from "./config-schema-gen.ts";
import { GEN_TASKS, INTEGRATIONS } from "./names.ts";
import { powersyncGenSchema } from "./powersync/config-schema.ts";

const strings = v.array(v.string());
const stringRecord = v.record(v.string(), v.string());

const EXPOSE_PRIVILEGE =
  /^(?:select|insert|update|delete|(?:select|insert|update)\s*\(\s*(?:[a-z_][a-z0-9_$]*(?:\s*,\s*[a-z_][a-z0-9_$]*)*|\*(?:\s*,\s*-\s*[a-z_][a-z0-9_$]*)*)\s*\))$/;

// SAFETY: EXPOSE_PRIVILEGE accepts only the strings ExposePrivilege
// describes. A guard action would make a failed item untyped, and the
// expose union would then report one message instead of one per item.
const privilege = v.pipe(
  v.string(),
  v.regex(
    EXPOSE_PRIVILEGE,
    'Use select, insert, update or delete, name columns such as "update(title, body)", or exclude them from every column with "select(*, -secret)"',
  ),
) as v.GenericSchema<string, ExposePrivilege>;

const privileges = v.array(privilege);

const triggerValue: v.GenericSchema<TopicTriggerValueConfig> = v.union([
  v.string(),
  v.strictObject({
    from: v.string(),
    via: v.lazy(() => triggerValue),
    select: v.string(),
    key: v.exactOptional(v.string()),
  }),
]);

const triggerValues = v.record(v.string(), triggerValue);

const isGenerator = (value: unknown): value is Generator =>
  typeof value === "object" &&
  value !== null &&
  "name" in value &&
  typeof value.name === "string" &&
  "generate" in value &&
  typeof value.generate === "function";

const generator = v.custom<Generator>(
  isGenerator,
  "must be a generator: { name, generate(input) }",
);

/**
 * The top level of `better-supabase.config.*`. It rejects unknown keys and
 * checks the leaves a typo or an old value breaks; nested objects the library
 * reads loosely stay loose.
 */
const entityName = v.pipe(
  v.string(),
  v.regex(
    /^[a-z][a-z0-9_]{0,40}$/,
    "an entity name is lowercase letters, digits and underscores",
  ),
);

const ADOPT_REMOVED =
  'ownership "adopt" was removed: a block now leaves alone every table your schema already has. Delete the key, or run `better-supabase codemod`.';

const instanceKeys = {
  block: v.optional(v.string()),
  on: v.optional(
    v.union([strings, v.record(v.string(), v.record(v.string(), v.unknown()))]),
  ),
  uses: v.optional(stringRecord),
  tables: v.optional(v.record(v.string(), v.nullable(v.string()))),
};

const blockEntries = {
  ...instanceKeys,
  ownership: v.optional(
    v.picklist(["managed", "custom"], (issue) =>
      issue.input === "adopt" ? ADOPT_REMOVED : issue.message,
    ),
  ),
  schema: v.optional(v.string()),
  columns: v.optional(
    v.record(v.string(), v.record(v.string(), v.nullable(v.string()))),
  ),
  values: v.optional(blockSchemas.valueMapsSchema),
  idType: v.optional(v.string()),
  owner: v.optional(v.picklist(["tenant", "user", "none"])),
  ownTablePolicies: v.optional(v.picklist(["block", "app"])),
  tenantScope: v.optional(blockSchemas.tenantScopeSchema),
  functions: v.optional(stringRecord),
  permissions: v.optional(stringRecord),
  names: v.optional(
    v.union([
      entityName,
      v.record(
        v.string(),
        v.union([
          entityName,
          v.strictObject({
            name: v.optional(entityName),
            plural: v.optional(entityName),
            url: v.optional(v.string()),
            subject: v.optional(v.literal(false)),
            team: v.optional(v.strictObject({ actions: strings })),
            auditReads: v.optional(v.boolean()),
          }),
        ]),
      ),
    ]),
  ),
  options: v.optional(v.record(v.string(), v.unknown())),
  callbacks: v.optional(
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
      v.literal(false),
      v.strictObject({ schema: v.string(), functions: v.optional(strings) }),
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

const activeTenantSource = v.union([
  v.picklist(["claim", "resolver"]),
  v.strictObject({ profileColumn: v.string(), key: v.optional(v.string()) }),
]);

const permissionsBlock = v.strictObject({
  ...blockEntries,
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
  scopes: v.optional(v.record(v.string(), strings)),
  disabled: v.optional(
    v.strictObject({
      tenant: v.optional(v.union([v.string(), disabledRow])),
      user: v.optional(v.union([v.string(), disabledRow])),
      userKey: v.optional(v.string()),
    }),
  ),
  activeTenant: v.optional(activeTenantSource),
});

/**
 * `blocks`: a list of names, or each block's config. The schema checks the keys
 * every block shares; `resolveConfig` checks the tables, columns, functions,
 * actions, hooks and entities each module declares.
 */
// SAFETY: resolveConfig checks the names `BlocksConfig` narrows per module.
const blocksSchema = v.lazy((input) =>
  Array.isArray(input)
    ? strings
    : v.objectWithRest(
        { permissions: v.optional(permissionsBlock) },
        v.strictObject(blockEntries),
      ),
) as v.GenericSchema<unknown, readonly string[] | BlocksConfig>;

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
    teamIdsOf: v.optional(v.string()),
    canAssign: v.optional(v.string()),
    canAssignFor: v.optional(v.string()),
    permissionsFor: v.optional(v.string()),
    canApprove: v.optional(v.string()),
    isApprover: v.optional(v.string()),
    holdersOf: v.optional(v.string()),
    actorMayWrite: v.optional(v.string()),
    permitted: v.optional(v.string()),
    rowsWith: v.optional(v.string()),
    rowsWithFor: v.optional(v.string()),
    portalSubjects: v.optional(v.string()),
    portalParties: v.optional(v.string()),
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
  operations: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        permission: v.pipe(v.string(), v.minLength(1)),
        meta: v.optional(
          v.strictObject({
            risk: v.optional(v.picklist(["low", "medium", "high"])),
            effects: v.optional(
              v.array(v.picklist(["read", "write", "delete", "external"])),
            ),
            title: v.optional(v.string()),
          }),
        ),
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
        rolesTable: v.optional(v.string()),
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
      activeOrganizationFrom: v.optional(activeTenantSource),
      ownedClaims: v.pipe(strings, v.minLength(1, "List at least one claim")),
      truncatedClaim: v.optional(v.string()),
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
  versions: v.optional(blockSchemas.authorizationVersionsSchema),
  delegation: v.optional(
    v.strictObject({ scopes: v.optional(v.record(v.string(), strings)) }),
  ),
  approvals: v.optional(
    v.strictObject({ distinctApprover: v.optional(v.boolean()) }),
  ),
  problems: v.optional(strings),
});

const checkedAuthorization = v.pipe(
  authorization,
  v.rawCheck(({ dataset, addIssue }) => {
    if (!dataset.typed) {
      return;
    }

    for (const problem of scopeProblems(dataset.value)) {
      addIssue({ message: problem });
    }
  }),
);

const jsonSchema = v.record(v.string(), v.unknown());

const presetInstance = v.strictObject({
  ...instanceKeys,
  names: v.optional(stringRecord),
  subjects: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        team: v.optional(v.strictObject({ actions: strings })),
        auditReads: v.optional(v.boolean()),
      }),
    ),
  ),
  options: v.optional(jsonSchema),
});

const onDelete = v.optional(v.picklist(APP_ON_DELETE_ACTIONS));

const appTableEntries = {
  columns: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        type: v.picklist(APP_COLUMN_TYPES),
        nullable: v.optional(v.boolean()),
        default: v.optional(v.string()),
        unique: v.optional(v.boolean()),
        references: v.optional(
          v.union([
            v.strictObject({ table: v.string(), onDelete }),
            v.strictObject({ block: v.string(), table: v.string(), onDelete }),
          ]),
        ),
        format: v.optional(v.picklist(APP_COLUMN_FORMATS)),
        options: v.optional(v.array(v.string())),
        min: v.optional(v.number()),
        max: v.optional(v.number()),
        comment: v.optional(v.string()),
        identity: v.optional(v.boolean()),
        access: v.optional(v.picklist(APP_COLUMN_ACCESS)),
        encrypted: v.optional(v.boolean()),
        lookup: v.optional(v.boolean()),
      }),
    ),
  ),
  timestamps: v.optional(v.boolean()),
  id: v.optional(v.picklist(["uuid", "bigint"])),
  unique: v.optional(v.array(v.array(v.string()))),
  indexes: v.optional(v.array(v.array(v.string()))),
  comment: v.optional(v.string()),
  auditReads: v.optional(v.boolean()),
  subject: v.optional(
    v.strictObject({
      type: v.string(),
      title: v.optional(v.string()),
      url: v.optional(v.string()),
      search: v.optional(
        v.strictObject({
          title: v.optional(v.string()),
          body: v.optional(v.array(v.string())),
        }),
      ),
      permissions: v.optional(v.record(v.string(), v.string())),
      rank: v.optional(
        v.union([
          v.literal(true),
          v.strictObject({ group: v.optional(v.string()) }),
        ]),
      ),
      softDelete: v.optional(v.boolean()),
      versions: v.optional(
        v.union([
          v.literal(true),
          v.strictObject({
            columns: v.optional(strings),
            auto: v.optional(v.boolean()),
          }),
        ]),
      ),
    }),
  ),
  rollups: v.optional(
    v.record(
      v.string(),
      v.strictObject({
        table: v.string(),
        via: v.string(),
        aggregate: v.picklist(APP_ROLLUP_AGGREGATES),
        column: v.optional(v.string()),
        where: v.optional(
          v.strictObject({ column: v.string(), equals: v.string() }),
        ),
      }),
    ),
  ),
  lookups: v.optional(
    v.record(
      v.string(),
      v.strictObject({ via: v.string(), column: v.string() }),
    ),
  ),
  events: v.optional(
    v.union([
      v.literal(true),
      v.strictObject({
        on: v.optional(v.array(v.picklist(APP_TABLE_EVENT_KINDS))),
        include: v.optional(strings),
      }),
    ]),
  ),
};

const appTableOwner = v.optional(v.picklist(["inherit", "user", "none"]));

const appTables = v.record(
  v.string(),
  v.strictObject({ ...appTableEntries, owner: appTableOwner }),
);

/** A `/create` design keeps `scope` until designs move to the config shape. */
const designAppTables = v.record(
  v.string(),
  v.strictObject({ ...appTableEntries, scope: appTableOwner }),
);

const FLAT = {
  source: v.optional(sourceSchema),
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
  recordTypes: v.optional(v.boolean()),
  hooks: v.optional(hooksSchema),
  json: v.optional(
    v.record(
      v.string(),
      v.union(
        [
          v.strictObject({
            import: v.string(),
            schema: v.optional(jsonSchema),
          }),
          v.strictObject({ type: v.string(), schema: v.optional(jsonSchema) }),
        ],
        "Use { import } or { type }, with an optional schema",
      ),
    ),
  ),
  codecs: v.optional(
    v.strictObject({
      timestamptz: v.optional(v.picklist(["string", "instant", "utc"])),
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
  generators: v.optional(v.array(generator)),
  organization: v.optional(
    v.strictObject({
      column: v.optional(v.string()),
      onMissing: v.optional(v.picklist(["error", "skip"])),
      header: v.optional(v.string()),
    }),
  ),
  claims: v.optional(
    v.strictObject({
      scope: v.optional(v.string()),
      features: v.optional(v.string()),
      memberships: v.optional(v.string()),
      permissions: v.optional(v.string()),
    }),
  ),
  buckets: v.optional(v.record(v.string(), bucketSchema)),
  topics: v.optional(stringRecord),
  realtime: v.optional(
    v.strictObject({
      tables: v.optional(strings),
      global: v.optional(strings),
      users: v.optional(stringRecord),
      policies: v.optional(
        v.strictObject({ from: strings, output: v.string() }),
      ),
      triggers: v.optional(
        v.array(
          v.strictObject({
            topic: v.string(),
            table: v.string(),
            values: v.optional(triggerValues),
            events: v.optional(
              v.array(v.picklist(["insert", "update", "delete"])),
            ),
            event: v.optional(
              v.union([
                v.string(),
                v.strictObject({
                  insert: v.optional(v.string()),
                  update: v.optional(v.string()),
                  delete: v.optional(v.string()),
                }),
              ]),
            ),
            payload: v.optional(
              v.union([
                v.picklist(["keys", "row"]),
                v.record(
                  v.string(),
                  v.union([triggerValue, v.strictObject({ sql: v.string() })]),
                ),
              ]),
            ),
            topics: v.optional(
              v.array(
                v.strictObject({
                  topic: v.string(),
                  values: v.optional(triggerValues),
                }),
              ),
            ),
            functionSchema: v.optional(v.string()),
            when: v.optional(
              v.strictObject({
                changed: v.pipe(v.array(v.string()), v.minLength(1)),
              }),
            ),
          }),
        ),
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
  subjects: v.optional(
    v.record(
      v.pipe(
        v.string(),
        v.regex(
          /^[a-z][a-z0-9_-]{0,62}$/,
          "a subject type is lowercase letters, digits, hyphens and underscores",
        ),
      ),
      v.strictObject({
        table: v.string(),
        id: v.optional(v.string()),
        idType: v.optional(v.string()),
        tenant: v.optional(v.union([v.string(), v.literal(false)])),
        title: v.optional(v.string()),
        url: v.optional(v.string()),
        permissions: v.optional(blockSchemas.subjectPermissionsSchema),
        scope: v.optional(v.string()),
        cascade: v.optional(v.boolean()),
        history: v.optional(v.array(v.string())),
        deletedAt: v.optional(v.string()),
        held: v.optional(v.string()),
        readAccess: v.optional(v.picklist(["tenant", "record"])),
        team: v.optional(v.strictObject({ actions: strings })),
        auditReads: v.optional(v.boolean()),
        search: v.optional(blockSchemas.subjectSearchSchema),
        rank: v.optional(
          v.strictObject({ column: v.string(), group: v.optional(v.string()) }),
        ),
        versions: v.optional(
          v.strictObject({ columns: strings, auto: v.boolean() }),
        ),
      }),
    ),
  ),
  appTables: v.optional(appTables),
  blocks: v.optional(blocksSchema),
  sql: v.optional(
    v.strictObject({
      workflow: v.optional(v.picklist(["pg-delta", "migra", "migrations"])),
      dir: v.optional(v.string()),
      prefix: v.optional(v.string()),
      testsDir: v.optional(v.string()),
      schema: v.optional(v.string()),
      api: v.optional(v.string()),
      owner: v.optional(v.picklist(["tenant", "user", "none"])),
      ownTablePolicies: v.optional(v.picklist(["block", "app"])),
      tenantScope: v.optional(blockSchemas.tenantScopeSchema),
      tenantColumn: v.optional(v.string()),
    }),
  ),
  seed: v.optional(
    v.strictObject({
      entry: v.optional(v.string()),
      output: v.optional(v.string()),
      perTenant: v.optional(v.string()),
    }),
  ),
  openapi: v.optional(
    v.strictObject({
      entry: v.optional(v.string()),
      output: v.optional(v.string()),
    }),
  ),
  specs: v.optional(
    v.strictObject({
      entry: v.optional(v.string()),
      outputs: v.optional(
        v.array(
          v.strictObject({
            format: v.pipe(v.string(), v.minLength(1)),
            version: v.optional(v.string()),
            output: v.optional(v.string()),
            overlays: v.optional(strings),
            serialize: v.optional(v.picklist(["json", "yaml"])),
            ui: v.optional(
              v.picklist(["scalar", "swagger", "redoc", "elements", "rapidoc"]),
            ),
          }),
        ),
      ),
      failOn: v.optional(v.picklist(["error", "warning", "never"])),
      manifest: v.optional(v.string()),
    }),
  ),
  doctor: v.optional(
    v.strictObject({
      ignore: v.optional(strings),
      only: v.optional(strings),
      strict: v.optional(v.boolean()),
      format: v.optional(v.picklist(["text", "sarif", "github"])),
      output: v.optional(v.string()),
      sources: v.optional(strings),
      policyHelperLimit: v.optional(v.number()),
      sealTriggers: v.optional(strings),
      claimsLimit: v.optional(v.number()),
      migrationSafety: v.optional(
        v.strictObject({ since: v.optional(v.string()) }),
      ),
      baseline: v.optional(v.string()),
    }),
  ),
  env: v.optional(
    v.strictObject({
      output: v.optional(v.string()),
      prefix: v.optional(v.string()),
    }),
  ),
  integrations: v.optional(v.array(v.picklist(INTEGRATIONS))),
  skills: v.optional(
    v.strictObject({ agents: v.optional(v.array(v.picklist(SKILLS_AGENTS))) }),
  ),
  keys: v.optional(v.strictObject({ output: v.optional(v.string()) })),
};

const pickEntries = <const K extends keyof typeof FLAT>(
  keys: readonly K[],
): Pick<typeof FLAT, K> =>
  // SAFETY: every key comes from FLAT, so the picked object has exactly K.
  Object.fromEntries(keys.map((key) => [key, FLAT[key]])) as Pick<
    typeof FLAT,
    K
  >;

const ENTRIES = {
  database: v.optional(
    v.strictObject(
      pickEntries([
        "source",
        "schemas",
        "sql",
        "seed",
        "expose",
        "buckets",
        "realtime",
        "topics",
        "vectorSearch",
      ]),
    ),
  ),
  auth: v.optional(
    v.strictObject({
      tenant: v.optional(
        v.strictObject({
          claim: v.optional(v.string()),
          column: v.optional(v.string()),
          onMissing: v.optional(v.picklist(["error", "skip"])),
          header: v.optional(v.string()),
        }),
      ),
      ...pickEntries(["claims", "authorization", "entitlements"]),
    }),
  ),
  subjects: FLAT.subjects,
  blocks: FLAT.blocks,
  adapters: FLAT.integrations,
  gen: v.optional(
    v.strictObject({
      tasks: v.optional(v.array(v.picklist(GEN_TASKS))),
      watchInterval: v.optional(
        v.pipe(v.number(), v.minValue(1, "must be a positive number of ms")),
      ),
      contentMapper: v.optional(v.boolean()),
      powersync: v.optional(powersyncGenSchema),
      ...pickEntries([
        "output",
        "casing",
        "postgrestVersion",
        "recordTypes",
        "hooks",
        "tables",
        "json",
        "codecs",
        "relations",
        "sensitive",
        "storagePaths",
        "functions",
        "generators",
        "readSets",
      ]),
    }),
  ),
  api: v.optional(v.strictObject(pickEntries(["openapi", "specs"]))),
  tooling: v.optional(
    v.strictObject(pickEntries(["doctor", "env", "keys", "skills"])),
  ),
} satisfies { [K in keyof Required<EnvironmentConfig>]: v.GenericSchema };

const EnvironmentSchema = v.strictObject(ENTRIES);

/**
 * The shape of a `/create` design; `parseDesign` adds the rules a schema can't
 * state.
 */
/**
 * A preset name, or the conventions that differ from the defaults and the
 * blocks.
 */
const PresetSchema = v.union([
  v.pipe(v.string(), v.minLength(1)),
  v.strictObject({
    ...Object.fromEntries(
      CONVENTION_FIELDS.map((field) => [
        field.key,
        v.optional(
          field.multi === true
            ? v.array(v.picklist(field.values))
            : v.picklist(field.values),
        ),
      ]),
    ),
    blocks: v.optional(v.array(v.string())),
    instances: v.optional(v.record(v.string(), presetInstance)),
  }),
]);

const DesignSchema = v.strictObject({
  version: v.optional(v.pipe(v.number(), v.integer(), v.minValue(0))),
  preset: v.optional(PresetSchema),
  appTables: v.optional(designAppTables),
  extraColumns: v.optional(v.record(v.string(), stringRecord)),
  positions: v.optional(
    v.record(v.string(), v.pipe(v.array(v.number()), v.length(2))),
  ),
});

const ConfigSchema = v.strictObject({
  $schema: v.optional(v.string()),
  preset: v.optional(PresetSchema),
  ...ENTRIES,
  $env: v.optional(v.record(v.string(), EnvironmentSchema)),
  $development: v.optional(EnvironmentSchema),
  $production: v.optional(EnvironmentSchema),
  $test: v.optional(EnvironmentSchema),
  $ci: v.optional(EnvironmentSchema),
} satisfies { [K in keyof Required<BetterSupabaseConfig>]: v.GenericSchema });

/** Each issue as `path: message`, the path in config keys. */
export function configIssues(value: unknown): string[] {
  const moved = movedKeyIssues(value);

  if (moved.length > 0) {
    return moved;
  }

  const auth =
    typeof value === "object" && value !== null && "auth" in value
      ? value.auth
      : undefined;

  if (
    typeof value === "object" &&
    value !== null &&
    typeof auth === "object" &&
    auth !== null &&
    "authorization" in auth
  ) {
    const provider = auth.authorization;

    const problem =
      typeof provider === "object" && provider !== null
        ? providerApiProblem(provider)
        : undefined;

    if (problem !== undefined) {
      const { authorization: _, ...rest } = auth;

      return [
        `auth.authorization.apiVersion: ${problem}`,
        ...configIssues({ ...value, auth: rest }),
      ];
    }
  }

  const result = v.safeParse(ConfigSchema, value);

  if (result.success) {
    return [];
  }

  return result.issues.map((issue) => {
    const path = v.getDotPath(issue);

    return path ? `${path}: ${issue.message}` : issue.message;
  });
}

/** Every path where the schema and `BetterSupabaseConfig` disagree. */
type ConfigDrift = ParityPaths<
  v.InferOutput<typeof ConfigSchema>,
  BetterSupabaseConfig
>;

/**
 * Adds a `drift` key naming the paths, so `satisfies` fails while there are
 * any.
 */
type InStep<T, Drift> = [Drift] extends [never] ? T : T & { drift: Drift };

/**
 * The schemas `scripts/gen-config-schema.ts` renders into
 * `schemas/config-v1.json`.
 */
export interface ConfigSchemas {
  readonly config: v.GenericSchema;
  readonly environment: v.GenericSchema;
  readonly moduleConfig: v.GenericSchema;
  readonly permissionsBlock: v.GenericSchema;
  readonly privilege: v.GenericSchema;
  readonly triggerValue: v.GenericSchema;
  /** Checked by a function, so the renderer writes its JSON Schema. */
  readonly generator: v.GenericSchema;
  /** A `/create` design, rendered into `schemas/design-v1.json`. */
  readonly design: v.GenericSchema;
}

const SCHEMAS = {
  config: ConfigSchema,
  environment: EnvironmentSchema,
  moduleConfig: v.strictObject(blockEntries),
  permissionsBlock,
  privilege,
  triggerValue,
  generator,
  design: DesignSchema,
} satisfies InStep<ConfigSchemas, ConfigDrift>;

export const configSchemas = (): ConfigSchemas => SCHEMAS;
