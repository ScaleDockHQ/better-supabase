import type { AnyBlocksConfig, BlockScope } from "../config/blocks.ts";
import type {
  BlockSqlDefinition,
  BlockSqlLayout,
  BlockSql,
} from "./module-types.ts";

import { BLOCK_SCOPES } from "../config/blocks.ts";
import { applyActorWriteGuards } from "./actor-guard.ts";
import { renamedBlock } from "./block-renames.ts";
import { migrationOptionUses } from "./migration-options.ts";
import { bindModuleRegistry, moduleContext } from "./module-context.ts";
import { ACCESS_REQUESTS } from "./modules/access-requests.ts";
import { ENGAGEMENTS } from "./modules/activities.ts";
import { AGENTS_MODULE } from "./modules/agents.ts";
import { AI_CACHE } from "./modules/ai-cache.ts";
import { AI_CHAT } from "./modules/ai-chat.ts";
import { AI_FILES } from "./modules/ai-files.ts";
import { AI_PROVIDERS } from "./modules/ai-keys.ts";
import { AI_TASKS } from "./modules/ai-schedules.ts";
import { ANNOUNCEMENTS } from "./modules/announcements.ts";
import { API_KEYS } from "./modules/api-keys.ts";
import { APPROVALS } from "./modules/approvals.ts";
import { ASSETS } from "./modules/assets.ts";
import { ASSIGNMENT } from "./modules/assignment.ts";
import { ATTACHMENTS } from "./modules/attachments.ts";
import { AUDIT } from "./modules/audit.ts";
import { RULES } from "./modules/automations.ts";
import { BILLABLE_TIME } from "./modules/billable-time.ts";
import { BILLING } from "./modules/billing.ts";
import { BOOKINGS } from "./modules/bookings.ts";
import { BULK } from "./modules/bulk.ts";
import { CALENDAR } from "./modules/calendar.ts";
import { CATALOG } from "./modules/catalog.ts";
import { CHANNELS } from "./modules/channels.ts";
import { CHAT_SDK_STATE } from "./modules/chat-sdk-state.ts";
import { COLLECTIONS } from "./modules/collections.ts";
import { COMMENTS } from "./modules/comments.ts";
import { CONTROLS } from "./modules/compliance.ts";
import { CONNECTORS } from "./modules/connectors.ts";
import { PARTIES } from "./modules/contacts.ts";
import { CONTENT } from "./modules/content.ts";
import { CONTRACTS } from "./modules/contracts.ts";
import { COURSES } from "./modules/courses.ts";
import { ACTOR } from "./modules/created-by.ts";
import { CREDENTIALS } from "./modules/credentials.ts";
import { CUSTOM_FIELDS } from "./modules/custom-fields.ts";
import { DATA_LIFECYCLE } from "./modules/data-lifecycle.ts";
import { DEALS } from "./modules/deals.ts";
import { DISPATCH } from "./modules/dispatch.ts";
import { DOCUMENTS } from "./modules/documents.ts";
import { DOMAINS } from "./modules/domains.ts";
import { DONATIONS } from "./modules/donations.ts";
import { DRIVE, DRIVE_FILES } from "./modules/drive.ts";
import { EMPLOYEES } from "./modules/employees.ts";
import { ENRICHMENT } from "./modules/enrichment.ts";
import { ENROLLMENTS } from "./modules/enrollments.ts";
import { ENTITLEMENTS } from "./modules/entitlements.ts";
import { EXPENSES } from "./modules/expenses.ts";
import { FIELD_ENCRYPTION } from "./modules/field-encryption.ts";
import { FIELD_HISTORY } from "./modules/field-history.ts";
import { FLAGS } from "./modules/flags.ts";
import { FORECASTS } from "./modules/forecasts.ts";
import { FORMS } from "./modules/forms.ts";
import { TARGETS } from "./modules/goals.ts";
import { GRANTS } from "./modules/grants.ts";
import { GUESTS } from "./modules/guests.ts";
import { HIRING } from "./modules/hiring.ts";
import { IDEMPOTENCY } from "./modules/idempotency.ts";
import { IDENTITIES } from "./modules/identities.ts";
import { IMPORTS } from "./modules/imports.ts";
import { INBOX } from "./modules/inbox.ts";
import { INCIDENTS } from "./modules/incidents.ts";
import { INVENTORY } from "./modules/inventory.ts";
import { INVITATIONS } from "./modules/invitations.ts";
import { INVOICES } from "./modules/invoices.ts";
import { JSONB_SCHEMAS } from "./modules/jsonb-schemas.ts";
import { KNOWLEDGE } from "./modules/knowledge.ts";
import { LEAD_SCORING } from "./modules/lead-scoring.ts";
import { LEASES } from "./modules/leases.ts";
import { LEAVE } from "./modules/leave.ts";
import { LEDGER } from "./modules/ledger.ts";
import { MAIL_SYNC } from "./modules/mail-sync.ts";
import { TENANT } from "./modules/memberships.ts";
import { MEMORY } from "./modules/memory.ts";
import { MESSAGING } from "./modules/messaging.ts";
import { METRICS } from "./modules/metrics.ts";
import { MFA } from "./modules/mfa.ts";
import { MODERATION } from "./modules/moderation.ts";
import { NOTIFICATIONS } from "./modules/notifications.ts";
import { NUMBER_SEQUENCES } from "./modules/numbering.ts";
import { OAUTH_SERVER } from "./modules/oauth-server.ts";
import { ONBOARDING } from "./modules/onboarding.ts";
import { ORDERS } from "./modules/orders.ts";
import { ORGANIZATIONS } from "./modules/organizations.ts";
import { OUTBOX } from "./modules/outbox.ts";
import { PASSES } from "./modules/passes.ts";
import { ACCESS } from "./modules/permissions.ts";
import { PGTAP } from "./modules/pgtap.ts";
import { PIPELINES } from "./modules/pipelines.ts";
import { POSTS } from "./modules/posts.ts";
import { PROFILES } from "./modules/profiles.ts";
import { PROMOTIONS } from "./modules/promotions.ts";
import { PUSH } from "./modules/push.ts";
import { JOBS } from "./modules/queue.ts";
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
import { ENSURE_RLS } from "./modules/rls-guard.ts";
import { SAVED_VIEWS } from "./modules/saved-views.ts";
import { SCORES } from "./modules/scores.ts";
import { SEARCH } from "./modules/search.ts";
import { SHARED_SIGNALS } from "./modules/security-events.ts";
import { SEGMENTS } from "./modules/segments.ts";
import { SEQUENCES } from "./modules/sequences.ts";
import { SERVICE_PRINCIPALS } from "./modules/service-accounts.ts";
import { SESSIONS } from "./modules/sessions.ts";
import { SETTINGS } from "./modules/settings.ts";
import { SHARE_LINKS } from "./modules/share-links.ts";
import { SHIPMENTS } from "./modules/shipments.ts";
import { SIGNATURES } from "./modules/signatures.ts";
import { SIGNING_KEYS } from "./modules/signing-keys.ts";
import { SLA } from "./modules/sla.ts";
import { SSO } from "./modules/sso.ts";
import { STATE_MACHINE } from "./modules/state-machine.ts";
import { STREAMS } from "./modules/streams.ts";
import { SUBJECTS } from "./modules/subjects.ts";
import { SUPPORT_SESSIONS } from "./modules/support.ts";
import { TAGS } from "./modules/tags.ts";
import { WORK_ITEMS } from "./modules/tasks.ts";
import { TEAMS } from "./modules/teams.ts";
import { TEMPLATES } from "./modules/templates.ts";
import { TIME_TRACKING } from "./modules/time-tracking.ts";
import { ACTIVITY } from "./modules/timeline.ts";
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
import { WORKFLOW_BUILDER } from "./modules/workflow-editor.ts";
import { WORKFLOW_SDK_WORLD } from "./modules/workflow-sdk.ts";
import { WORKFLOWS } from "./modules/workflows.ts";
import { applyTenantScope } from "./tenant-scope.ts";

function built(definition: BlockSqlDefinition): BlockSql {
  let cached: string | undefined;

  return {
    ...definition,
    get sql() {
      if (cached === undefined) {
        const ctx = moduleContext(definition.name, {});

        cached = applyActorWriteGuards(
          applyTenantScope(definition.build(ctx, {}), ctx),
          {},
        );
      }

      return cached;
    },
  };
}

// Outside tenant scope a module checks the caller itself, so the tenant
// module and the access contract drop from what it needs. They are what
// tenant scope runs on, so they always run in it.
const TENANT_PROVIDERS: ReadonlySet<string> = new Set([
  "memberships",
  "permissions",
]);

/**
 * The scope `name` runs in for `layout`: its own, then `sql.scope`, then
 * `tenant`.
 */
export function blockScope(name: string, layout: BlockSqlLayout): BlockScope {
  if (TENANT_PROVIDERS.has(name)) {
    return "tenant";
  }

  return layout.modules?.[name]?.scope ?? layout.scope ?? "tenant";
}

const requiresOf = (
  module: BlockSql,
  layout: BlockSqlLayout,
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
  module: BlockSql,
  layout: BlockSqlLayout,
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

  return `blocks.${module.name}: the ${module.name} module runs in ${scopes.join(" or ")} scope, not ${scope}${own ? "" : " (from database.sql.owner)"}. ${scopes.includes("tenant") ? `Set blocks.${module.name}.owner to "tenant" or remove the block.` : "Remove the block."}`;
}

/** New modules go at the end: the position is part of the file name. */
export const SQL_MODULES: Readonly<Record<string, BlockSql>> =
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
      built(MODERATION),
      built(REVIEWS),
      built(LEAVE),
      built(RULES),
      built(VERCEL_MARKETPLACE),
      built(LEDGER),
      built(ASSETS),
      built(SCORES),
      built(ENROLLMENTS),
      built(GUESTS),
      built(PASSES),
      built(BILLABLE_TIME),
      built(LEASES),
      built(EXPENSES),
      built(DONATIONS),
      built(DISPATCH),
      built(SHIPMENTS),
      built(CONTRACTS),
      built(CONTROLS),
      built(INCIDENTS),
      built(COURSES),
      built(MESSAGING),
      built(CHANNELS),
      built(ACTIVITY),
      built(MAIL_SYNC),
      built(SEGMENTS),
      built(ASSIGNMENT),
      built(ENRICHMENT),
      built(FORECASTS),
      built(FIELD_HISTORY),
      built(SEQUENCES),
      built(LEAD_SCORING),
      built(POSTS),
      built(FIELD_ENCRYPTION),
      built(CONTENT),
      built(ENSURE_RLS),
    ].map((module) => [module.name, module]),
  );

export const ORDER: readonly string[] = Object.keys(SQL_MODULES);

/** Where a module renders: its own position, or just ahead of `before`. */
function renderPosition(module: BlockSql): number {
  return module.before === undefined
    ? ORDER.indexOf(module.name)
    : ORDER.indexOf(module.before) - 0.5;
}

bindModuleRegistry({ modules: SQL_MODULES, resolve: resolveBlocks });

/**
 * The modules to install for `names`, dependencies first. Throws on an unknown
 * name.
 */
export function resolveBlocks(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): BlockSql[] {
  const ordered: BlockSql[] = [];

  const visit = (name: string, from?: string): void => {
    const module = SQL_MODULES[name];

    if (!module) {
      const renamed = renamedBlock(name);

      throw new TypeError(
        renamed === undefined
          ? `Unknown SQL module "${name}"${from ? ` (required by ${from})` : ""}. Available: ${Object.keys(SQL_MODULES).join(", ")}`
          : `The "${name}" block is named "${renamed}" since 0.15. Run \`better-supabase codemod 0.15\` to rename it in your config and imports.`,
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
  registry: Readonly<Record<string, BlockSql>> = SQL_MODULES,
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
      name === "queue" &&
      entry?.schema !== undefined &&
      entry.schema !== "better_supabase"
    ) {
      throw new TypeError(
        "blocks.queue.schema: the queue block always installs in better_supabase. Remove schema.",
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
