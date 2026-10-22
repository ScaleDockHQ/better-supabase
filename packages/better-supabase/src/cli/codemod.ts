/**
 * Source rewrites for `better-supabase codemod`. A small scanner masks strings,
 * template literals and comments, so renames only touch code; there is no
 * parser dependency, so each transform is a narrow, mechanical rename.
 */

import type { CliCallMigration } from "./codemod-calls.ts";
import type { ConfigEdit } from "./sql/config-edit.ts";
import type { WebhookFormat } from "./sql/config-webhook-format.ts";

import { BLOCK_EVENT_RENAMES } from "../events/index.ts";
import { codeRanges } from "./code-ranges.ts";
import {
  CLI_CALL_FILE,
  cliCallHints,
  rewriteCliCalls,
  SHELL_FILE,
} from "./codemod-calls.ts";
import { migrateCliCall } from "./core/moved.ts";
import { mask } from "./sql/config-edit.ts";
import { groupConfigJson, groupConfigSource } from "./sql/config-group.ts";
import {
  moveSqlModulesToBlocks,
  moveSqlModulesToBlocksJson,
} from "./sql/config-move.ts";
import { pinWebhookFormat } from "./sql/config-webhook-format.ts";

/**
 * `better-supabase.config.*`, the files a codemod's `configFile` edit applies
 * to.
 */
export const CONFIG_FILE: RegExp =
  /(?:^|[\\/])better-supabase\.config\.(?:ts|mts|cts|js|mjs|cjs|json)$/;

export interface Codemod {
  readonly name: string;
  readonly description: string;
  /**
   * Exported names, renamed in imports from `better-supabase` and where the
   * import is used.
   */
  readonly imports?: Readonly<Record<string, string>>;
  /**
   * Local bindings, renamed where a file declares or imports them and imports
   * from `better-supabase` or a `supabase` module.
   */
  readonly bindings?: Readonly<Record<string, string>>;
  /** Member names, renamed after a `.` anywhere in code. */
  readonly members?: readonly MemberRename[];
  /** JSX props on one component. */
  readonly props?: readonly PropRename[];
  /** Keys of the options object a named call takes, at its top level. */
  readonly options?: readonly OptionRename[];
  /** Option keys added where a default changed, to keep the old behavior. */
  readonly pins?: readonly OptionPin[];
  /**
   * Whole string literals, such as event types, renamed in strings, templates
   * and comments.
   */
  readonly strings?: Readonly<Record<string, string>>;
  /** Changes too ambiguous to rewrite; matching lines are listed for review. */
  readonly review?: readonly ReviewHint[];
  /** A rewrite of `better-supabase.config.*`; a refusal is listed for review. */
  readonly configFile?: (source: string, json: boolean) => CodemodConfigEdit;
  /**
   * Renamed CLI calls, rewritten in `package.json` and workflows and listed in
   * other shell files.
   */
  readonly cliCalls?: CliCallMigration;
  /**
   * CLI calls left as they are, listed for review in scripts, workflows and
   * shell files.
   */
  readonly cliReview?: readonly ReviewHint[];
}

export interface ReviewLine {
  readonly line: number;
  readonly message: string;
}

/** A config rewrite, with the lines it changed that need a look. */
export type CodemodConfigEdit =
  | ConfigEdit
  | {
      readonly ok: true;
      readonly text: string;
      readonly review: readonly ReviewLine[];
    };

export interface MemberRename {
  readonly from: string;
  readonly to: string;
  /** Skip a member followed by `(`, when the old name is still a method. */
  readonly notCalled?: boolean;
}

export interface PropRename {
  readonly component: string;
  readonly from: string;
  readonly to: string;
}

export interface OptionRename {
  readonly call: string;
  readonly from: string;
  readonly to: string;
}

export interface OptionPin {
  readonly call: string;
  /** 0-based position of the options object among the call's arguments. */
  readonly argument: number;
  readonly key: string;
  /** The code written as the key's value. */
  readonly value: string;
  /** Keys whose presence means the call needs no pin. */
  readonly unless?: readonly string[];
  /**
   * Pins only in files this matches; other calls without the key are listed for
   * review.
   */
  readonly when: RegExp;
  readonly message: string;
}

export interface ReviewHint {
  readonly pattern: RegExp;
  readonly message: string;
}

/**
 * Offset pages show up as `.page` (the envelope or the parsed query),
 * `pageCount`, `totalPages`, a `page` key, or a `page` URL param.
 */
const PAGE_UI =
  /\.page\b(?!\s*\()|\bpageCount\b|\btotalPages\b|\bpage\s*:|[?&]page=|["']page["']/;

const OFFSET_PIN = {
  key: "pagination",
  value: '"offset"',
  when: PAGE_UI,
  message:
    'Lists and resources page by cursor (`after`, `nextCursor`, no total) unless `pagination: "offset"` is set. This file shows no page numbers, so the codemod left it: add `pagination: "offset"` if a UI elsewhere reads `page` or the total, or the list sorts by a relation',
} as const;

/** Review lines for `sql.modules` left in environment blocks after the move. */
function environmentModules(text: string): ReviewLine[] {
  return mask(text)
    .split("\n")
    .flatMap((line, index) =>
      /\bmodules\s*:/.test(line)
        ? [
            {
              line: index + 1,
              message:
                "`sql.modules` in an environment block moves to `blocks` too",
            },
          ]
        : [],
    );
}

/**
 * `edit` with `defaultFormat` pinned to `format` where an adopted webhooks-out
 * block needs it.
 */
function withWebhookFormat(
  edit: CodemodConfigEdit,
  json: boolean,
  format: WebhookFormat,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const earlier = "review" in edit ? edit.review : [];
  const pin = pinWebhookFormat(edit.text, json, format);

  if (pin === undefined) {
    return { ok: true, text: edit.text, review: earlier };
  }

  if (!pin.ok) {
    return {
      ok: true,
      text: edit.text,
      review: [
        ...earlier,
        {
          line: 1,
          message: `blocks["webhooks-out"] is adopted and maps no columns.endpoints.format, but defaultFormat wasn't pinned: ${pin.reason}. Set options.defaultFormat to "${format}" to keep the body endpoints get now`,
        },
      ],
    };
  }

  const line =
    pin.text.split("\n").findIndex((text) => text.includes("defaultFormat")) +
    1;

  return {
    ok: true,
    text: pin.text,
    review: [
      ...earlier,
      {
        line: Math.max(line, 1),
        message: `blocks["webhooks-out"] is adopted and maps no columns.endpoints.format, so the codemod set options.defaultFormat to "${format}", the body its endpoints get now. Change it if your receivers expect the other format`,
      },
    ],
  };
}

const SQL_ADD_HINT: ReviewHint = {
  pattern: /(?<![\w.@-])(?:better-supabase|bsb)(?:@[\w.^~-]+)?\s+sql\s+add\b/,
  message:
    "`sql add` still only writes the block's SQL; `add` also wires its clients and config. Use `add` unless the script needs the SQL alone",
};

const BLOCK_SQL_TYPES =
  "Context ContractFunction Names Layout File IdType AccessProvider EntitlementsProvider TableSpec Upgrade PermissionKey Audit Deprecation Extension Emit UpgradePlan Topic TestFile Action";

const ENTITY_FORM_TYPES =
  " CustomField Field Input Options Result State Values";

/** `from` and `to` prefixed to each space-separated suffix in `suffixes`. */
function prefixed(
  from: string,
  to: string,
  suffixes: string,
): Record<string, string> {
  return Object.fromEntries(
    suffixes.split(" ").map((suffix) => [from + suffix, to + suffix]),
  );
}

export const CODEMODS: Readonly<Record<string, Codemod>> = {
  "0.4": {
    name: "0.4",
    description: "Renames from 0.3 to 0.4 (the naming page lists them)",
    imports: {
      createBrowser: "createClient",
      BetterBrowser: "BetterClient",
      BrowserOptions: "ClientOptions",
      BrowserAuth: "ClientAuth",
      BetterEnv: "HonoEnv",
      HandlerOptions: "MiddlewareOptions",
      Queries: "BetterQueries",
      CreateQueriesOptions: "QueriesOptions",
      Postgres: "BetterPostgres",
      DefineSupabaseOptions: "SupabaseOptions",
    },
    members: [
      { from: "serverFor", to: "contextForSession" },
      { from: "toORPCError", to: "toOrpcError" },
      { from: "$table", to: "$tableName", notCalled: true },
    ],
    props: [
      { component: "BetterSupabaseProvider", from: "browser", to: "client" },
    ],
    review: [
      {
        pattern: /\.server\(\)/,
        message:
          "`next.server()` is `bsb.context()` on the createNext() instance",
      },
      {
        pattern: /\.handle\(\)/,
        message: "Hono's `bsb.handle()` is `bsb.handler()`",
      },
      {
        pattern: /\bmcp\.handler\b/,
        message: "`mcp.handler` is `bsb.endpoint`",
      },
      { pattern: /\.sb\b/, message: "`client.sb` is `client.betterSupabase`" },
      {
        pattern: /\btestExecutor\(\s*\{[^}]*\bsb\b/,
        message: "`{ sb }` in testExecutor is `{ betterSupabase }`",
      },
    ],
  },
  "0.5": {
    name: "0.5",
    description:
      "Renames from 0.4 to 0.5: createMcp's scopes is advertisedScopes",
    options: [{ call: "createMcp", from: "scopes", to: "advertisedScopes" }],
  },
  "0.6": {
    name: "0.6",
    description:
      "Changes from 0.5 to 0.6: kits become blocks and modules, org becomes organization (in event types too), $rpc returns table rows and records in the configured casing, and bucket publicUrl() and path() return a Result",
    strings: { ...BLOCK_EVENT_RENAMES, "org.*": "organization.*" },
    imports: {
      KitEvent: "BlockEvent",
      KitEventMap: "BlockEventMap",
      KitEventType: "BlockEventType",
      KitEventMeta: "BlockEventMeta",
      KitEventPattern: "BlockEventPattern",
      KitEventsMatching: "BlockEventsMatching",
      onKitEvent: "onBlockEvent",
      forwardKitEvents: "forwardBlockEvents",
      ForwardKitOptions: "ForwardBlockOptions",
      KIT_ATTRIBUTES: "BLOCK_ATTRIBUTES",
      kitCloudEvent: "blockCloudEvent",
      kitEventAttributes: "blockEventAttributes",
      traceKitEvents: "traceBlockEvents",
      KitTransport: "BlockTransport",
      OrgEventData: "OrganizationEventData",
      createOrgs: "createOrganizations",
      Orgs: "Organizations",
      OrgsOptions: "OrganizationsOptions",
      CreateOrgOptions: "CreateOrganizationOptions",
      OrgAttributes: "OrganizationAttributes",
      orgLogoBucket: "organizationLogoBucket",
      OrgLogoBucketOptions: "OrganizationLogoBucketOptions",
      KitsConfig: "BlocksConfig",
      KitModuleConfig: "BlockConfig",
      KitMode: "BlockMode",
      AccessKitConfig: "AccessBlockConfig",
      renderKit: "renderModules",
      kitLayout: "moduleLayout",
      kitPermissionKeys: "modulePermissionKeys",
      kitDeprecations: "moduleDeprecations",
      kitFilePaths: "moduleFilePaths",
      kitFileVersion: "moduleFileVersion",
      sameKitFile: "sameModuleFile",
      kitIdType: "moduleIdType",
      isKitIdType: "isModuleIdType",
      KIT_ID_TYPES: "MODULE_ID_TYPES",
      KitIdType: "ModuleIdType",
      KitContext: "ModuleContext",
      KitLayout: "ModuleLayout",
      KitFile: "ModuleFile",
      KitNames: "ModuleNames",
      KitTableSpec: "ModuleTableSpec",
      KitContractFunction: "ModuleContractFunction",
      KitDeprecation: "ModuleDeprecation",
      KitPermissionKey: "ModulePermissionKey",
      KitUpgrade: "ModuleUpgrade",
      KitUpgradePlan: "ModuleUpgradePlan",
      InstalledKitModule: "InstalledModule",
    },
    options: [
      { call: "defineSupabase", from: "maxUrlLength", to: "urlLengthLimit" },
    ],
    review: [
      {
        pattern:
          /from\s*["']better-supabase\/(orgs|jobs|notifications|webhooks)["']/,
        message:
          "This subpath moved under `better-supabase/blocks/` (`orgs` is `blocks/organizations`; the outbox, entitlements and audit retention left `jobs` for their own blocks); the 0.5 to 0.6 guide maps each export",
      },
      {
        pattern:
          /\bcreateInbox\b[^\n]*from\s*["']better-supabase\/(blocks\/)?jobs["']/,
        message:
          "The webhook inbox is `createWebhookInbox` from `better-supabase/blocks/jobs`; `createInbox` is now the conversation inbox in `blocks/inbox`",
      },
      {
        pattern: /\$rpc\s*(<|\()/,
        message:
          "`$rpc` now returns table rows and `returns table (...)` records in the configured casing, with codecs applied: drop a snake-to-camel mapping of the result, or pass `{ raw: true }` to keep database names. Scalar results and `returns table` columns are now `| null` unless `functions.<name>.notNull` says otherwise",
      },
      {
        pattern: /\.publicUrl\s*\(/,
        message:
          "A connected bucket's `publicUrl()` returns a `Result` instead of throwing: read `.data` (`null` on an error) or check `.ok`",
      },
      {
        pattern: /\.path\s*\(\s*\{/,
        message:
          "A bucket definition's `path(values)` returns a `Result` instead of throwing, like the connected client's `path()`: read `.data` (`null` on an error) or check `.ok`",
      },
    ],
  },
  "0.9": {
    name: "0.9",
    description:
      "Moves sql.modules to the top-level blocks key in better-supabase.config.*, rewrites CLI calls in package.json scripts and GitHub workflows to the new subcommands and flags (other shell files are listed), renames the config types (ModulesConfig to BlocksConfig, ModuleConfig to BlockConfig, AccessModuleConfig to AccessBlockConfig, ModuleMode to BlockMode), pins pagination: 'offset' on lists and resources in files that read page numbers, and lists behaviour changes for review: support sessions (denied without authorize, approved by a second admin), canApprove (now isApprover), outgoing webhook transforms and receivers (CloudEvents), gatewayOptions callers, generic problem types (about:blank), the delegation cap, role helpers, event and schedule starts (runAs), workflow builders, delivery and realtime fan-out, agent actors, share links, before_promotion_activate and comment subjects",
    imports: {
      ModulesConfig: "BlocksConfig",
      ModuleConfig: "BlockConfig",
      AccessModuleConfig: "AccessBlockConfig",
      ModuleMode: "BlockMode",
    },
    configFile: (source, json) => {
      const moved = json
        ? moveSqlModulesToBlocksJson(source)
        : moveSqlModulesToBlocks(source);

      return withWebhookFormat(
        moved.ok && !json
          ? { ...moved, review: environmentModules(moved.text) }
          : moved,
        json,
        "standard",
      );
    },
    cliCalls: migrateCliCall,
    cliReview: [SQL_ADD_HINT],
    pins: [
      { call: "defineListQuery", argument: 2, ...OFFSET_PIN },
      { call: "defineResource", argument: 2, unless: ["list"], ...OFFSET_PIN },
    ],
    review: [
      {
        pattern: /\bresources\s*:\s*\{/,
        message:
          'The default list of each `defineApi` resource pages by cursor (`after`, `nextCursor`) unless the table has no primary key; set `pagination: "offset"` on a resource whose clients send `page` or read the total',
      },
      {
        pattern: /\bsupportSessions\s*\(/,
        message:
          'Support sessions refuse every start without `authorize` (or the server\'s `authorization.support.authorize`), and a start needs a request approved by a different admin unless `policy.approval` is `"none"`. `authorize: "store"` keeps the store-only check',
      },
      {
        pattern: /\bcanApprove\b/,
        message:
          "`authorization.functions.canApprove` is deprecated: set `isApprover` with `{kind}` (`'ai-tool'`), `{subject}` (the tool name, was `{tool}`) and `{tenant}`",
      },
      {
        pattern: /\bcreateWebhooks\s*\(/,
        message:
          "Outgoing webhooks send CloudEvents 1.0 (`application/cloudevents+json`) instead of `{ type, timestamp, data }`; a `transform` now returns only the event's `data`, and receivers read `data` from the CloudEvent. `sql upgrade` keeps existing endpoints on `format = 'standard'` (the 0.8 body) until you set each one to `cloudevents`",
      },
      {
        pattern: /\bgatewayOptions\s*\(/,
        message:
          "`gatewayOptions` ignores a `user` in its second argument; pass the caller's id as `context.userId`",
      },
      {
        pattern:
          /bettersupabase\.com\/problems\/(invalid-request|unauthorized|forbidden|not-found|conflict|rate-limited|unexpected)\b|["'](Invalid request|Not found|Too many requests|Unexpected error)["']/,
        message:
          'Generic problems use `type: "about:blank"` and the HTTP status phrase as `title` (`Bad Request`, `Not Found`, `Too Many Requests`, `Internal Server Error`); match on `kind` or `code` instead',
      },
      {
        pattern: /\bpublish_webhook_event\s*\(/,
        message:
          "`publish_webhook_event` takes `subject` and `read_permission` and delivers only to endpoints whose owner may read the event",
      },
      {
        pattern: /\btoken_scope_allows\s*\(|["']oauth-client["']/,
        message:
          "Delegated tokens are narrowed inside `member_can`, `platform_can` and `tenant_ids_with`: a permission passes only when one of the token's scopes maps to it. Map scopes in `blocks.access.scopes` or `authorization.delegation.scopes`; a `token_scope_allows` check in a write policy is now covered by the cap",
      },
      {
        pattern:
          /\b(has_organization_role|member_organization_ids|organization_member_role)\s*\(/,
        message:
          "Under the provider model the role helpers take membership from the provider's `memberIds`, and a role name check skips the delegation cap (doctor BS334): check a permission with `tenant_ids_with('<permission>')` or `member_can()`",
      },
      {
        pattern: /\b(workflowStarter|startOnEvent)\s*\(/,
        message:
          "Event and schedule starts need `runAs: { publisher, permissions }` (or a function returning it): a schedule start without it throws, and the run's context is the publisher's, capped to `permissions`",
      },
      {
        pattern: /\bcreateBuilder\s*\(/,
        message:
          "Published versions run as their publisher (`versions.runAs`), and versions published before 0.9 fail with `WORKFLOW_PUBLISHER_REVOKED` until republished. A version the organization owns runs as its default service principal: create one with `default: true` or set `automation.runAs`",
      },
      {
        pattern: /\b(createNotifications|createReminders)\s*\(|\.fanOut\s*\(/,
        message:
          "Under an authorization provider without `delivery.subscribers` or `delivery.audience`, an event about a registered subject reaches only users who may read it (`subjectReaders`), and realtime `fanOut` refuses it (`REALTIME_SUBSCRIBER_POLICY_REQUIRED`) until you pass a `policy`",
      },
      {
        pattern: /\bkind\s*:\s*["']agent["']/,
        message:
          'An `act` level `{ kind: "agent", sub, tools }` is now valid (build it with `agentClaims`) and writes with the user\'s rights unless it sets `read_only: true`; `tools` must be a list of names',
      },
      {
        pattern: /\bcreate_share_link\b/,
        message:
          "`create_share_link` takes `version_id` and `expires_at` after `role`; grants and revokes on the four-argument signature must name `(uuid, text, text, text, uuid, timestamptz)`",
      },
      {
        pattern: /\bbefore_promotion_activate\b/,
        message:
          "`promotions` now calls `before_promotion_activate(promotion uuid)` after every write that leaves a promotion active; a function of that name runs on each such save",
      },
      {
        pattern: /\bcomments\s*:\s*\{/,
        message:
          "With `config.records` set and no `subjects` option, comments accept only the registered subject types and require read on the subject row",
      },
    ],
  },
  "0.11": {
    name: "0.11",
    description:
      'Pins blocks["webhooks-out"].options.defaultFormat to "cloudevents" in better-supabase.config.* when the block is adopted and maps no columns.endpoints.format, since adopt mode requires it from 0.11; the 0.9 codemod pins "standard" instead for configs coming from 0.8',
    configFile: (source, json) =>
      withWebhookFormat({ ok: true, text: source }, json, "cloudevents"),
  },
  "0.15": {
    name: "0.15",
    description:
      "Regroups better-supabase.config.* into database, auth, gen, api and tooling (subjects to records, appTables to tables, integrations to adapters, a block's mode, scope, entities and hooks to ownership, owner, names and callbacks, claims.tenant and the tenant plugin's column to auth.organization); renames the runtime instance bs to bsb (the CLI's short name) where a file creates, imports or destructures it, and the bs key on request contexts (ctx.bs, c.var.bs, locals.bs, context.bs) to bsb; renames imports: SqlModule to BlockSql, ModuleDefinition to BlockSqlDefinition and the other Module* SQL types to BlockSql*, SubjectRef to RecordRef, entityForm to recordForm, ShipmentCarrier to ShippingProvider, QueueBackend to QueueProvider; rewrites CLI calls in package.json scripts and GitHub workflows to the 0.15 commands (apply and adopt to add, sql sync and sql upgrade to upgrade, introspect to gen --save-snapshot, seed to db seed, env, run, keys and stack to dev); cache tags, query keys and the debug header and route that start with bs are listed for review",
    bindings: {
      bs: "bsb",
      SqlModule: "BlockSql",
      ModuleDefinition: "BlockSqlDefinition",
      ...prefixed("Module", "BlockSql", BLOCK_SQL_TYPES),
      ...prefixed("EntityForm", "RecordForm", ENTITY_FORM_TYPES),
      renderModules: "renderBlocks",
      resolveModules: "resolveBlocks",
      resolveModule: "resolveBlock",
      isModuleIdType: "isBlockSqlIdType",
      sameModuleFile: "sameBlockFile",
      InstalledModule: "InstalledBlock",
      SkippedModule: "SkippedBlock",
      SubjectRef: "RecordRef",
      entityForm: "recordForm",
      useEntityForm: "useRecordForm",
      UseEntityFormOptions: "UseRecordFormOptions",
      ShipmentCarrier: "ShippingProvider",
      testShipmentCarrier: "testShippingProvider",
      TestShipmentCarrierOptions: "TestShippingProviderOptions",
      QueueBackend: "QueueProvider",
      sqlQueueBackend: "sqlQueueProvider",
      testQueueBackend: "testQueueProvider",
      transportQueueBackend: "transportQueueProvider",
      vercelQueueBackend: "vercelQueueProvider",
      TestQueueBackendOptions: "TestQueueProviderOptions",
      TransportQueueBackendOptions: "TransportQueueProviderOptions",
      VercelQueueBackendOptions: "VercelQueueProviderOptions",
    },
    members: [{ from: "bs", to: "bsb" }],
    configFile: (source, json) =>
      json ? groupConfigJson(source) : groupConfigSource(source),
    cliCalls: migrateCliCall,
    review: [
      {
        pattern: /["'`]bs[:.]|\[\s*["']bs["']/,
        message:
          "Cache tags (`bsb:<table>`), query keys (`['bsb', ...]`) and workflow attributes (`bsb.tenant`) now start with `bsb`",
      },
      {
        pattern: /x-bs-db-calls|\/api\/bs-stats|\bbs-(?:proxy|verify)\b/,
        message:
          "The debug header is `x-bsb-db-calls`, the stats route `/api/bsb-stats`, and the Server-Timing names `bsb-proxy` and `bsb-verify`",
      },
      {
        pattern: /["'`]bs:t:/,
        message: "Realtime change topics are `bsb:t:<schema>.<table>`",
      },
    ],
  },
};

const SUPABASE_IMPORT =
  /\bfrom\s*["'](?:better-supabase(?:\/[\w./-]*)?|[^"']*supabase[^"']*)["']/;

/**
 * Renames bindings a file declares, destructures or imports, in files that
 * import from `better-supabase` or a `supabase` module.
 */
function renameBindings(
  text: string,
  bindings: Readonly<Record<string, string>>,
): string {
  const ranges = codeRanges(text);

  if (
    codeMatches(text, new RegExp(SUPABASE_IMPORT, "g"), ranges).length === 0
  ) {
    return text;
  }

  const renames = new Map(
    Object.entries(bindings).filter(([from]) => {
      const name = escapeRegExp(from);

      const declared = new RegExp(
        `\\b(?:const|let|var|function)\\s+${name}(?![\\w$])|[{,]\\s*(?:type\\s+)?${name}\\s*(?:[,}]|as\\b)|\\(\\s*${name}\\s*[:,)]`,
        "g",
      );

      return codeMatches(text, declared, ranges).length > 0;
    }),
  );

  return renameIdentifiers(text, renames);
}

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

function applyEdits(text: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.start - b.start)) {
    if (edit.start < cursor) {
      continue;
    }

    out += text.slice(cursor, edit.start) + edit.text;
    cursor = edit.end;
  }

  return out + text.slice(cursor);
}

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

function inCode(ranges: readonly [number, number][], index: number): boolean {
  let low = 0;
  let high = ranges.length - 1;

  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    const [start, end] = ranges[middle]!;

    if (index < start) {
      high = middle - 1;
    } else if (index >= end) {
      low = middle + 1;
    } else {
      return true;
    }
  }

  return false;
}

const OPENING = "({[";
const CLOSING = ")}]";

/** Matches of `pattern` that start in code. */
function codeMatches(
  text: string,
  pattern: RegExp,
  ranges: readonly [number, number][],
): RegExpExecArray[] {
  return [...text.matchAll(pattern)].filter((match) =>
    inCode(ranges, match.index),
  );
}

const IMPORT =
  /\b(import|export)\s+(type\s+)?\{([^}]*)\}\s*from\s*(["'])better-supabase(?:\/[\w./-]*)?\4/g;

function renameImports(
  text: string,
  renames: Readonly<Record<string, string>>,
): { text: string; locals: Set<string> } {
  const ranges = codeRanges(text);
  const locals = new Set<string>();
  const edits: Edit[] = [];

  for (const match of codeMatches(text, IMPORT, ranges)) {
    const list = match[3]!;
    const listStart = match.index + match[0].indexOf("{") + 1;

    const renamed = list.replaceAll(
      /(\btype\s+)?([\w$]+)(\s+as\s+[\w$]+)?/g,
      (spec, type: string | undefined, name: string, alias?: string) => {
        const to = renames[name];

        if (to === undefined) {
          return spec;
        }

        if (alias === undefined && match[1] === "import") {
          locals.add(name);
        }

        return `${type ?? ""}${to}${alias ?? ""}`;
      },
    );

    if (renamed !== list) {
      edits.push({
        start: listStart,
        end: listStart + list.length,
        text: renamed,
      });
    }
  }

  return { text: applyEdits(text, edits), locals };
}

function renameIdentifiers(
  text: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) {
    return text;
  }

  const ranges = codeRanges(text);
  const names = [...renames.keys()].map(escapeRegExp).join("|");
  const pattern = new RegExp(`(?<![\\w$.])(?:${names})(?![\\w$])`, "g");

  return applyEdits(
    text,
    codeMatches(text, pattern, ranges).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: renames.get(match[0])!,
    })),
  );
}

function renameStrings(
  text: string,
  strings: Readonly<Record<string, string>>,
): string {
  const names = Object.keys(strings).map(escapeRegExp).join("|");

  if (names === "") {
    return text;
  }

  const ranges = codeRanges(text);
  const pattern = new RegExp(`(["'\`])(${names})\\1`, "g");

  return applyEdits(
    text,
    [...text.matchAll(pattern)]
      .filter((match) => !inCode(ranges, match.index + 1))
      .map((match) => ({
        start: match.index + 1,
        end: match.index + 1 + match[2]!.length,
        text: strings[match[2]!]!,
      })),
  );
}

function renameMembers(text: string, members: readonly MemberRename[]): string {
  const ranges = codeRanges(text);

  const edits = members.flatMap((member) =>
    codeMatches(
      text,
      new RegExp(
        `\\.${escapeRegExp(member.from)}(?![\\w$])${member.notCalled === true ? "(?!\\s*\\()" : ""}`,
        "g",
      ),
      ranges,
    ).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: `.${member.to}`,
    })),
  );

  return applyEdits(text, edits);
}

function renameProps(text: string, props: readonly PropRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];

  for (const prop of props) {
    const tag = new RegExp(`<${escapeRegExp(prop.component)}(?![\\w$.])`, "g");

    for (const match of codeMatches(text, tag, ranges)) {
      let depth = 0;

      for (
        let index = match.index + match[0].length;
        index < text.length;
        index += 1
      ) {
        if (!inCode(ranges, index)) {
          continue;
        }

        const char = text[index]!;

        if (char === "{") {
          depth += 1;
        } else if (char === "}") {
          depth -= 1;
        } else if (char === ">" && depth === 0) {
          break;
        }

        if (
          depth === 0 &&
          /\s/.test(text[index - 1] ?? "") &&
          text.startsWith(`${prop.from}=`, index)
        ) {
          edits.push({
            start: index,
            end: index + prop.from.length,
            text: prop.to,
          });
        }
      }
    }
  }

  return applyEdits(text, edits);
}

/** The index after the bracket that closes the one at `open`, in code only. */
function closing(
  text: string,
  open: number,
  ranges: readonly [number, number][],
): number {
  let depth = 0;

  for (let index = open; index < text.length; index += 1) {
    if (!inCode(ranges, index)) {
      continue;
    }

    const char = text[index]!;

    if (OPENING.includes(char)) {
      depth += 1;
    } else if (CLOSING.includes(char)) {
      depth -= 1;

      if (depth === 0) {
        return index + 1;
      }
    }
  }

  return text.length;
}

/**
 * Calls `visit(index, depth)` for each code character from `open` to its
 * closing bracket.
 */
function walkBrackets(
  text: string,
  open: number,
  ranges: readonly [number, number][],
  visit: (index: number, depth: number, char: string) => void,
): void {
  const end = closing(text, open, ranges);
  let depth = 0;

  for (let index = open; index < end; index += 1) {
    if (!inCode(ranges, index)) {
      continue;
    }

    const char = text[index]!;

    if (OPENING.includes(char)) {
      depth += 1;
    } else if (CLOSING.includes(char)) {
      depth -= 1;
    }

    visit(index, depth, char);
  }
}

/** Where `key` is a top-level key of the object literal at `open`. */
function topLevelKeys(
  text: string,
  open: number,
  key: string,
  ranges: readonly [number, number][],
): { readonly index: number; readonly shorthand: boolean }[] {
  const keys: { index: number; shorthand: boolean }[] = [];
  let previous = "";
  walkBrackets(text, open, ranges, (index, depth, char) => {
    if (
      depth === 1 &&
      (previous === "{" || previous === ",") &&
      text.startsWith(key, index) &&
      !/[\w$]/.test(text[index + key.length] ?? "")
    ) {
      const after = /^\s*(\S)/.exec(text.slice(index + key.length))?.[1];

      if (after === ":") {
        keys.push({ index, shorthand: false });
      } else if (after === "," || after === "}") {
        keys.push({ index, shorthand: true });
      }
    }

    if (depth === 1 && !/\s/.test(char)) {
      previous = char;
    }
  });

  return keys;
}

function renameOptions(text: string, options: readonly OptionRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];

  for (const option of options) {
    const call = new RegExp(
      `(?<![\\w$.])${escapeRegExp(option.call)}\\s*(?:<[^>]*>)?\\s*\\(`,
      "g",
    );

    for (const match of codeMatches(text, call, ranges)) {
      const objects: number[] = [];
      walkBrackets(
        text,
        match.index + match[0].length - 1,
        ranges,
        (index, depth, char) => {
          if (depth === 2 && char === "{") {
            objects.push(index);
          }
        },
      );

      for (const object of objects) {
        for (const { index, shorthand } of topLevelKeys(
          text,
          object,
          option.from,
          ranges,
        )) {
          edits.push({
            start: index,
            end: index + option.from.length,
            text: shorthand ? `${option.to}: ${option.from}` : option.to,
          });
        }
      }
    }
  }

  return applyEdits(text, edits);
}

interface PinTarget {
  /** Where the call starts, for the review line. */
  readonly call: number;
  /** The edit that adds the key, or `undefined` when only a review fits. */
  readonly edit: Edit | undefined;
}

/** The arguments of the call whose `(` is at `open`: start and end of each. */
function callArguments(
  text: string,
  open: number,
  ranges: readonly [number, number][],
): { start: number; end: number }[] {
  const args: { start: number; end: number }[] = [];
  let start = open + 1;
  const end = closing(text, open, ranges) - 1;

  walkBrackets(text, open, ranges, (index, depth, char) => {
    if (depth === 1 && char === ",") {
      args.push({ start, end: index });
      start = index + 1;
    }
  });

  if (text.slice(start, end).trim() !== "") {
    args.push({ start, end });
  }

  return args;
}

/**
 * Calls of `pin.call` whose options object lacks `pin.key`, with the insertion
 * when one is safe.
 */
function pinTargets(text: string, pin: OptionPin): PinTarget[] {
  const ranges = codeRanges(text);

  const call = new RegExp(
    `(?<![\\w$.])${escapeRegExp(pin.call)}\\s*(?:<[^>]*>)?\\s*\\(`,
    "g",
  );

  const targets: PinTarget[] = [];
  const entry = `${pin.key}: ${pin.value}`;

  for (const match of codeMatches(text, call, ranges)) {
    const open = match.index + match[0].length - 1;
    const args = callArguments(text, open, ranges);
    const arg = args[pin.argument];

    if (arg === undefined) {
      if (args.length !== pin.argument) {
        targets.push({ call: match.index, edit: undefined });
        continue;
      }

      const last = args.at(-1);
      const at = last === undefined ? open + 1 : last.end;
      const trailing = text[at] === ",";

      targets.push({
        call: match.index,
        edit: trailing
          ? { start: at + 1, end: at + 1, text: ` { ${entry} }` }
          : { start: at, end: at, text: `, { ${entry} }` },
      });
      continue;
    }

    const offset = text.slice(arg.start, arg.end).search(/\S/);
    const object = arg.start + offset;

    if (text[object] !== "{") {
      targets.push({ call: match.index, edit: undefined });
      continue;
    }

    const keys = [pin.key, ...(pin.unless ?? [])];

    if (
      keys.some((key) => topLevelKeys(text, object, key, ranges).length > 0)
    ) {
      continue;
    }

    const spreads: number[] = [];
    walkBrackets(text, object, ranges, (index, depth) => {
      if (depth === 1 && text.startsWith("...", index)) {
        spreads.push(index);
      }
    });

    if (spreads.length > 0) {
      targets.push({ call: match.index, edit: undefined });
      continue;
    }

    const body = text.slice(object + 1, closing(text, object, ranges) - 1);
    const first = /^[ \t]*\n([ \t]*)\S/.exec(body);

    targets.push({
      call: match.index,
      edit:
        body.trim() === ""
          ? {
              start: object,
              end: object + body.length + 2,
              text: `{ ${entry} }`,
            }
          : first
            ? {
                start: object + 1,
                end: object + 1,
                text: `\n${first[1]!}${entry},`,
              }
            : { start: object + 1, end: object + 1, text: ` ${entry},` },
    });
  }

  return targets;
}

function pinOptions(
  text: string,
  pins: readonly OptionPin[],
): { text: string; review: { line: number; message: string }[] } {
  let out = text;

  for (const pin of pins) {
    if (pin.when.test(out)) {
      out = applyEdits(
        out,
        pinTargets(out, pin).flatMap((target) =>
          target.edit === undefined ? [] : [target.edit],
        ),
      );
    }
  }

  const review = pins.flatMap((pin) =>
    pinTargets(out, pin).map((target) => ({
      line: out.slice(0, target.call).split("\n").length,
      message: pin.message,
    })),
  );

  return { text: out, review };
}

export interface CodemodResult {
  readonly text: string;
  /** 1-based lines that need a manual change, with the reason. */
  readonly review: readonly {
    readonly line: number;
    readonly message: string;
  }[];
}

/** Applies one codemod to a source file. */
export function applyCodemod(
  codemod: Codemod,
  source: string,
  file?: string,
): CodemodResult {
  if (
    file !== undefined &&
    (CLI_CALL_FILE.test(file) || SHELL_FILE.test(file))
  ) {
    const hints = linesMatching(source, codemod.cliReview ?? []);

    if (!codemod.cliCalls) {
      return { text: source, review: hints };
    }

    return CLI_CALL_FILE.test(file)
      ? { text: rewriteCliCalls(source, codemod.cliCalls), review: hints }
      : {
          text: source,
          review: [...cliCallHints(source, codemod.cliCalls), ...hints],
        };
  }

  let text = source;
  const refused: { line: number; message: string }[] = [];

  if (codemod.configFile && file !== undefined && CONFIG_FILE.test(file)) {
    const json = file.endsWith(".json");
    const edit = codemod.configFile(source, json);

    if (edit.ok) {
      text = edit.text;
      refused.push(...("review" in edit ? edit.review : []));
    } else {
      refused.push({
        line: 1,
        message: `The config wasn't rewritten: ${edit.reason}`,
      });
    }

    if (json) {
      return { text, review: refused };
    }
  }

  if (codemod.imports) {
    const imported = renameImports(text, codemod.imports);
    text = renameIdentifiers(
      imported.text,
      new Map(
        [...imported.locals].map((name) => [name, codemod.imports![name]!]),
      ),
    );
  }

  if (codemod.bindings) {
    text = renameBindings(text, codemod.bindings);
  }

  if (codemod.members) {
    text = renameMembers(text, codemod.members);
  }

  if (codemod.props) {
    text = renameProps(text, codemod.props);
  }

  if (codemod.options) {
    text = renameOptions(text, codemod.options);
  }

  if (codemod.strings) {
    text = renameStrings(text, codemod.strings);
  }

  if (codemod.pins) {
    const pinned = pinOptions(text, codemod.pins);
    text = pinned.text;
    refused.push(...pinned.review);
  }

  return {
    text,
    review: [...refused, ...linesMatching(text, codemod.review ?? [])],
  };
}

/** One review line per line of `text` that a hint's pattern matches. */
function linesMatching(
  text: string,
  hints: readonly ReviewHint[],
): ReviewLine[] {
  return hints.flatMap((hint) =>
    text
      .split("\n")
      .flatMap((line, index) =>
        hint.pattern.test(line)
          ? [{ line: index + 1, message: hint.message }]
          : [],
      ),
  );
}
