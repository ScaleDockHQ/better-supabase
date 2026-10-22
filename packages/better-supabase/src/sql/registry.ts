import type { AnyBlocksConfig, BlockScope } from "../config/blocks.ts";
import type {
  ModuleDefinition,
  ModuleLayout,
  SqlModule,
} from "./module-types.ts";

import { BLOCK_SCOPES } from "../config/blocks.ts";
import { applyActorWriteGuards } from "./actor-guard.ts";
import { migrationOptionUses } from "./migration-options.ts";
import { bindModuleRegistry, moduleContext } from "./module-context.ts";
import { ACCESS_REQUESTS } from "./modules/access-requests.ts";
import { ACCESS } from "./modules/access.ts";
import { ACTOR } from "./modules/actor.ts";
import { AGENTS_MODULE } from "./modules/agents.ts";
import { AI_CACHE } from "./modules/ai-cache.ts";
import { AI_CHAT } from "./modules/ai-chat.ts";
import { AI_FILES } from "./modules/ai-files.ts";
import { AI_PROVIDERS } from "./modules/ai-providers.ts";
import { AI_TASKS } from "./modules/ai-tasks.ts";
import { ANNOUNCEMENTS } from "./modules/announcements.ts";
import { API_KEYS } from "./modules/api-keys.ts";
import { APPROVALS } from "./modules/approvals.ts";
import { ATTACHMENTS } from "./modules/attachments.ts";
import { AUDIT } from "./modules/audit.ts";
import { BILLING } from "./modules/billing.ts";
import { BOOKINGS } from "./modules/bookings.ts";
import { BULK } from "./modules/bulk.ts";
import { CALENDAR } from "./modules/calendar.ts";
import { CATALOG } from "./modules/catalog.ts";
import { CHAT_SDK_STATE } from "./modules/chat-sdk-state.ts";
import { COLLECTIONS } from "./modules/collections.ts";
import { COMMENTS } from "./modules/comments.ts";
import { CONNECTORS } from "./modules/connectors.ts";
import { CREDENTIALS } from "./modules/credentials.ts";
import { CUSTOM_FIELDS } from "./modules/custom-fields.ts";
import { DATA_LIFECYCLE } from "./modules/data-lifecycle.ts";
import { DEALS } from "./modules/deals.ts";
import { DOCUMENTS } from "./modules/documents.ts";
import { DOMAINS } from "./modules/domains.ts";
import { DRIVE, DRIVE_FILES } from "./modules/drive.ts";
import { EMPLOYEES } from "./modules/employees.ts";
import { ENGAGEMENTS } from "./modules/engagements.ts";
import { ENSURE_RLS } from "./modules/ensure-rls.ts";
import { ENTITLEMENTS } from "./modules/entitlements.ts";
import { FLAGS } from "./modules/flags.ts";
import { FORMS } from "./modules/forms.ts";
import { GRANTS } from "./modules/grants.ts";
import { HIRING } from "./modules/hiring.ts";
import { IDEMPOTENCY } from "./modules/idempotency.ts";
import { IDENTITIES } from "./modules/identities.ts";
import { IMPORTS } from "./modules/imports.ts";
import { INBOX } from "./modules/inbox.ts";
import { INVENTORY } from "./modules/inventory.ts";
import { INVITATIONS } from "./modules/invitations.ts";
import { INVOICES } from "./modules/invoices.ts";
import { JOBS } from "./modules/jobs.ts";
import { JSONB_SCHEMAS } from "./modules/jsonb-schemas.ts";
import { KNOWLEDGE } from "./modules/knowledge.ts";
import { LEAVE } from "./modules/leave.ts";
import { LEDGER } from "./modules/ledger.ts";
import { MEMORY } from "./modules/memory.ts";
import { METRICS } from "./modules/metrics.ts";
import { MFA } from "./modules/mfa.ts";
import { NOTIFICATIONS } from "./modules/notifications.ts";
import { NUMBER_SEQUENCES } from "./modules/number-sequences.ts";
import { OAUTH_SERVER } from "./modules/oauth-server.ts";
import { ONBOARDING } from "./modules/onboarding.ts";
import { ORDERS } from "./modules/orders.ts";
import { ORGANIZATIONS } from "./modules/organizations.ts";
import { OUTBOX } from "./modules/outbox.ts";
import { PARTIES } from "./modules/parties.ts";
import { PGTAP } from "./modules/pgtap.ts";
import { PIPELINES } from "./modules/pipelines.ts";
import { PROFILES } from "./modules/profiles.ts";
import { PROMOTIONS } from "./modules/promotions.ts";
import { PUSH } from "./modules/push.ts";
import { QUOTES } from "./modules/quotes.ts";
import { RANK } from "./modules/rank.ts";
import { RATE_LIMIT } from "./modules/rate-limit.ts";
import { REACTIONS } from "./modules/reactions.ts";
import { READ_SETS } from "./modules/read-sets.ts";
import { REALTIME_TABLES } from "./modules/realtime-tables.ts";
import { RELATIONS } from "./modules/relations.ts";
import { REMINDERS } from "./modules/reminders.ts";
import { RESERVED_SLUGS } from "./modules/reserved-slugs.ts";
import { REVIEWS } from "./modules/reviews.ts";
import { RULES } from "./modules/rules.ts";
import { SAVED_VIEWS } from "./modules/saved-views.ts";
import { SEARCH } from "./modules/search.ts";
import { SERVICE_PRINCIPALS } from "./modules/service-principals.ts";
import { SESSIONS } from "./modules/sessions.ts";
import { SETTINGS } from "./modules/settings.ts";
import { SHARE_LINKS } from "./modules/share-links.ts";
import { SHARED_SIGNALS } from "./modules/shared-signals.ts";
import { SIGNATURES } from "./modules/signatures.ts";
import { SIGNING_KEYS } from "./modules/signing-keys.ts";
import { SLA } from "./modules/sla.ts";
import { SSO } from "./modules/sso.ts";
import { STATE_MACHINE } from "./modules/state-machine.ts";
import { STREAMS } from "./modules/streams.ts";
import { SUBJECTS } from "./modules/subjects.ts";
import { SUPPORT_SESSIONS } from "./modules/support.ts";
import { TAGS } from "./modules/tags.ts";
import { TARGETS } from "./modules/targets.ts";
import { TEAMS } from "./modules/teams.ts";
import { TEMPLATES } from "./modules/templates.ts";
import { TENANT } from "./modules/tenant.ts";
import { TIME_TRACKING } from "./modules/time-tracking.ts";
import { TRASH } from "./modules/trash.ts";
import { UPDATED_AT } from "./modules/updated-at.ts";
import { USAGE } from "./modules/usage.ts";
import { VECTOR_SEARCH } from "./modules/vector-search.ts";
import { VERCEL_MARKETPLACE } from "./modules/vercel-marketplace.ts";
import { VERSIONS } from "./modules/versions.ts";
import { WAITLIST } from "./modules/waitlist.ts";
import { WEBHOOK_INBOX } from "./modules/webhook-inbox.ts";
import { WEBHOOKS_IN } from "./modules/webhooks-in.ts";
import { WEBHOOKS_OUT } from "./modules/webhooks-out.ts";
import { WORK_ITEMS } from "./modules/work-items.ts";
import { WORKFLOW_BUILDER } from "./modules/workflow-builder.ts";
import { WORKFLOW_SDK_WORLD } from "./modules/workflow-sdk-world.ts";
import { WORKFLOWS } from "./modules/workflows.ts";

function built(definition: ModuleDefinition): SqlModule {
  let cached: string | undefined;

  return {
    ...definition,
    get sql() {
      return (cached ??= applyActorWriteGuards(
        definition.build(moduleContext(definition.name, {}), {}),
        {},
      ));
    },
  };
}

// Outside tenant scope a module checks the caller itself, so the tenant
// module and the access contract drop from what it needs. They are what
// tenant scope runs on, so they always run in it.
const TENANT_PROVIDERS: ReadonlySet<string> = new Set(["tenant", "access"]);

/**
 * The scope `name` runs in for `layout`: its own, then `sql.scope`, then
 * `tenant`.
 */
export function blockScope(name: string, layout: ModuleLayout): BlockScope {
  if (TENANT_PROVIDERS.has(name)) {
    return "tenant";
  }

  return layout.modules?.[name]?.scope ?? layout.scope ?? "tenant";
}

const requiresOf = (
  module: SqlModule,
  layout: ModuleLayout,
): readonly string[] => {
  const requires =
    module.dependencies?.(layout) ??
    (layout.entitlementsProvider && module.providerRequires
      ? module.providerRequires
      : module.requires);

  return blockScope(module.name, layout) === "tenant"
    ? requires
    : requires.filter((name) => !TENANT_PROVIDERS.has(name));
};

/**
 * Why `module` can't run in its scope for `layout`, or undefined. The tenant
 * module and the access contract run wherever a tenant-scoped module needs
 * them.
 */
function scopeProblem(
  module: SqlModule,
  layout: ModuleLayout,
): string | undefined {
  if (TENANT_PROVIDERS.has(module.name)) {
    return undefined;
  }

  const scope = blockScope(module.name, layout);
  const scopes = module.scopes ?? BLOCK_SCOPES;

  if (scopes.includes(scope)) {
    return undefined;
  }

  const own = layout.modules?.[module.name]?.scope !== undefined;

  return `blocks.${module.name}: the ${module.name} module runs in ${scopes.join(" or ")} scope, not ${scope}${own ? "" : " (from sql.scope)"}. ${scopes.includes("tenant") ? `Set blocks.${module.name}.scope to "tenant" or remove the block.` : "Remove the block."}`;
}

/** New modules go at the end: the position is part of the file name. */
export const SQL_MODULES: Readonly<Record<string, SqlModule>> =
  Object.fromEntries(
    [
      built(UPDATED_AT),
      built(ACTOR),
      built(AUDIT),
      built(TENANT),
      built(INVITATIONS),
      built(RESERVED_SLUGS),
      built(JOBS),
      built(IDEMPOTENCY),
      built(WEBHOOK_INBOX),
      built(REALTIME_TABLES),
      built(JSONB_SCHEMAS),
      built(PGTAP),
      built(GRANTS),
      built(READ_SETS),
      built(MFA),
      built(ENTITLEMENTS),
      built(RATE_LIMIT),
      built(VECTOR_SEARCH),
      built(ACCESS),
      built(SUPPORT_SESSIONS),
      built(ORGANIZATIONS),
      built(PROFILES),
      built(OUTBOX),
      built(NOTIFICATIONS),
      built(WEBHOOKS_OUT),
      built(SESSIONS),
      built(WEBHOOKS_IN),
      built(API_KEYS),
      built(SETTINGS),
      built(USAGE),
      built(BILLING),
      built(FLAGS),
      built(COMMENTS),
      built(ATTACHMENTS),
      built(DATA_LIFECYCLE),
      built(SSO),
      built(ONBOARDING),
      built(WAITLIST),
      built(ANNOUNCEMENTS),
      built(STREAMS),
      built(CREDENTIALS),
      built(WORKFLOWS),
      built(WORKFLOW_SDK_WORLD),
      built(WORKFLOW_BUILDER),
      built(CHAT_SDK_STATE),
      built(INBOX),
      built(AI_CHAT),
      built(AI_FILES),
      built(KNOWLEDGE),
      built(MEMORY),
      built(AGENTS_MODULE),
      built(CONNECTORS),
      built(AI_TASKS),
      built(PUSH),
      built(AI_CACHE),
      built(AI_PROVIDERS),
      built(NUMBER_SEQUENCES),
      built(TEAMS),
      built(TAGS),
      built(STATE_MACHINE),
      built(CUSTOM_FIELDS),
      built(SHARE_LINKS),
      built(REMINDERS),
      built(IMPORTS),
      built(SUBJECTS),
      built(RANK),
      built(SAVED_VIEWS),
      built(RELATIONS),
      built(BULK),
      built(SEARCH),
      built(METRICS),
      built(CALENDAR),
      built(BOOKINGS),
      built(VERSIONS),
      built(TRASH),
      built(REACTIONS),
      built(APPROVALS),
      built(ACCESS_REQUESTS),
      built(DOCUMENTS),
      built(CATALOG),
      built(INVENTORY),
      built(DRIVE),
      built(DRIVE_FILES),
      built(ORDERS),
      built(PROMOTIONS),
      built(FORMS),
      built(SIGNATURES),
      built(TIME_TRACKING),
      built(IDENTITIES),
      built(SERVICE_PRINCIPALS),
      built(TEMPLATES),
      built(PIPELINES),
      built(PARTIES),
      built(ENGAGEMENTS),
      built(DEALS),
      built(WORK_ITEMS),
      built(QUOTES),
      built(INVOICES),
      built(SLA),
      built(TARGETS),
      built(HIRING),
      built(EMPLOYEES),
      built(COLLECTIONS),
      built(SIGNING_KEYS),
      built(SHARED_SIGNALS),
      built(OAUTH_SERVER),
      built(DOMAINS),
      built(REVIEWS),
      built(LEAVE),
      built(RULES),
      built(VERCEL_MARKETPLACE),
      built(LEDGER),
      built(ENSURE_RLS),
    ].map((module) => [module.name, module]),
  );

export const ORDER: readonly string[] = Object.keys(SQL_MODULES);

/** Where a module renders: its own position, or just ahead of `before`. */
function renderPosition(module: SqlModule): number {
  return module.before === undefined
    ? ORDER.indexOf(module.name)
    : ORDER.indexOf(module.before) - 0.5;
}

bindModuleRegistry({ modules: SQL_MODULES, resolve: resolveModules });

/**
 * The modules to install for `names`, dependencies first. Throws on an unknown
 * name.
 */
export function resolveModules(
  names: readonly string[],
  layout: ModuleLayout = {},
): SqlModule[] {
  const ordered: SqlModule[] = [];

  const visit = (name: string, from?: string): void => {
    const module = SQL_MODULES[name];

    if (!module) {
      throw new TypeError(
        `Unknown SQL module "${name}"${from ? ` (required by ${from})` : ""}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
      );
    }

    if (ordered.includes(module)) {
      return;
    }

    const problem = scopeProblem(module, layout);

    if (problem) {
      throw new TypeError(
        from ? `${problem} It is required by ${from}.` : problem,
      );
    }

    for (const dependency of requiresOf(module, layout)) {
      visit(dependency, name);
    }

    ordered.push(module);
  };

  for (const name of names) {
    visit(name);
  }

  return ordered.toSorted((a, b) => renderPosition(a) - renderPosition(b));
}

/**
 * Throws on a `blocks` key that names no module, or a mode a module doesn't
 * support.
 */
export function checkModules(
  config: AnyBlocksConfig = {},
  registry: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): void {
  for (const [name, entry] of Object.entries(config)) {
    const module = registry[name];

    if (!module) {
      throw new TypeError(
        `blocks.${name}: there is no SQL module "${name}". Modules: ${Object.keys(registry).join(", ")}`,
      );
    }

    // The jobs module writes everything into better_supabase, so a schema
    // would only point the modules that call it at functions that don't exist.
    if (
      name === "jobs" &&
      entry?.schema !== undefined &&
      entry.schema !== "better_supabase"
    ) {
      throw new TypeError(
        "blocks.jobs.schema: the jobs module always installs in better_supabase. Remove schema.",
      );
    }

    const mode = entry?.mode ?? "managed";
    const modes = module.modes ?? ["managed"];

    if (!modes.includes(mode)) {
      throw new TypeError(
        `blocks.${name}.mode: the ${name} module supports ${modes.join(", ")}, not ${mode}`,
      );
    }
  }

  for (const use of migrationOptionUses(config)) {
    if (!use.adopted) {
      throw new TypeError(
        `${use.message} Only adopt mode accepts it: set blocks.${use.module}.mode to "adopt" while you migrate an existing schema, or remove the option.`,
      );
    }
  }
}
