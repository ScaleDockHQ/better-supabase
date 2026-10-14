import type { ModulesConfig } from "../config/modules.ts";
import type { ModuleLayout } from "./module-types.ts";
import type { ModuleDefinition, SqlModule } from "./module-types.ts";

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
import { COMMENTS } from "./modules/comments.ts";
import { CONNECTORS } from "./modules/connectors.ts";
import { CREDENTIALS } from "./modules/credentials.ts";
import { CUSTOM_FIELDS } from "./modules/custom-fields.ts";
import { DATA_LIFECYCLE } from "./modules/data-lifecycle.ts";
import { DOCUMENTS } from "./modules/documents.ts";
import { DRIVE, DRIVE_FILES } from "./modules/drive.ts";
import { ENSURE_RLS } from "./modules/ensure-rls.ts";
import { ENTITLEMENTS } from "./modules/entitlements.ts";
import { FLAGS } from "./modules/flags.ts";
import { FORMS } from "./modules/forms.ts";
import { GRANTS } from "./modules/grants.ts";
import { IDEMPOTENCY } from "./modules/idempotency.ts";
import { IDENTITIES } from "./modules/identities.ts";
import { IMPORTS } from "./modules/imports.ts";
import { INBOX } from "./modules/inbox.ts";
import { INVENTORY } from "./modules/inventory.ts";
import { INVITATIONS } from "./modules/invitations.ts";
import { JOBS } from "./modules/jobs.ts";
import { JSONB_SCHEMAS } from "./modules/jsonb-schemas.ts";
import { KNOWLEDGE } from "./modules/knowledge.ts";
import { MEMORY } from "./modules/memory.ts";
import { METRICS } from "./modules/metrics.ts";
import { MFA } from "./modules/mfa.ts";
import { NOTIFICATIONS } from "./modules/notifications.ts";
import { NUMBER_SEQUENCES } from "./modules/number-sequences.ts";
import { ONBOARDING } from "./modules/onboarding.ts";
import { ORDERS } from "./modules/orders.ts";
import { ORGANIZATIONS } from "./modules/organizations.ts";
import { OUTBOX } from "./modules/outbox.ts";
import { PGTAP } from "./modules/pgtap.ts";
import { PROFILES } from "./modules/profiles.ts";
import { PROMOTIONS } from "./modules/promotions.ts";
import { PUSH } from "./modules/push.ts";
import { RANK } from "./modules/rank.ts";
import { RATE_LIMIT } from "./modules/rate-limit.ts";
import { REACTIONS } from "./modules/reactions.ts";
import { READ_SETS } from "./modules/read-sets.ts";
import { REALTIME_TABLES } from "./modules/realtime-tables.ts";
import { RELATIONS } from "./modules/relations.ts";
import { REMINDERS } from "./modules/reminders.ts";
import { RESERVED_SLUGS } from "./modules/reserved-slugs.ts";
import { SAVED_VIEWS } from "./modules/saved-views.ts";
import { SEARCH } from "./modules/search.ts";
import { SERVICE_PRINCIPALS } from "./modules/service-principals.ts";
import { SESSIONS } from "./modules/sessions.ts";
import { SETTINGS } from "./modules/settings.ts";
import { SHARE_LINKS } from "./modules/share-links.ts";
import { SIGNATURES } from "./modules/signatures.ts";
import { SSO } from "./modules/sso.ts";
import { STATE_MACHINE } from "./modules/state-machine.ts";
import { STREAMS } from "./modules/streams.ts";
import { SUBJECTS } from "./modules/subjects.ts";
import { SUPPORT_SESSIONS } from "./modules/support.ts";
import { TAGS } from "./modules/tags.ts";
import { TEAMS } from "./modules/teams.ts";
import { TEMPLATES } from "./modules/templates.ts";
import { TENANT } from "./modules/tenant.ts";
import { TIME_TRACKING } from "./modules/time-tracking.ts";
import { TRASH } from "./modules/trash.ts";
import { UPDATED_AT } from "./modules/updated-at.ts";
import { USAGE } from "./modules/usage.ts";
import { VECTOR_SEARCH } from "./modules/vector-search.ts";
import { VERSIONS } from "./modules/versions.ts";
import { WAITLIST } from "./modules/waitlist.ts";
import { WEBHOOK_INBOX } from "./modules/webhook-inbox.ts";
import { WEBHOOKS_IN } from "./modules/webhooks-in.ts";
import { WEBHOOKS_OUT } from "./modules/webhooks-out.ts";
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

const requiresOf = (
  module: SqlModule,
  layout: ModuleLayout,
): readonly string[] =>
  module.dependencies?.(layout) ??
  (layout.entitlementsProvider && module.providerRequires
    ? module.providerRequires
    : module.requires);

/** New modules go at the end: the position is part of the file name. */
export const SQL_MODULES: Readonly<Record<string, SqlModule>> =
  Object.fromEntries(
    [
      UPDATED_AT,
      ACTOR,
      built(AUDIT),
      built(TENANT),
      built(INVITATIONS),
      built(RESERVED_SLUGS),
      built(JOBS),
      IDEMPOTENCY,
      built(WEBHOOK_INBOX),
      REALTIME_TABLES,
      JSONB_SCHEMAS,
      PGTAP,
      GRANTS,
      READ_SETS,
      MFA,
      ENTITLEMENTS,
      RATE_LIMIT,
      VECTOR_SEARCH,
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
      ENSURE_RLS,
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

/** The modules to install for `names`, dependencies first. Throws on an unknown name. */
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
    if (ordered.includes(module)) return;
    for (const dependency of requiresOf(module, layout))
      visit(dependency, name);
    ordered.push(module);
  };
  for (const name of names) visit(name);
  return ordered.sort((a, b) => renderPosition(a) - renderPosition(b));
}

/** Throws on a `sql.modules` key that names no module, or a mode a module doesn't support. */
export function checkModules(
  config: ModulesConfig = {},
  registry: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): void {
  for (const [name, entry] of Object.entries(config)) {
    const module = registry[name];
    if (!module) {
      throw new TypeError(
        `sql.modules.${name}: there is no SQL module "${name}". Modules: ${Object.keys(registry).join(", ")}`,
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
        "sql.modules.jobs.schema: the jobs module always installs in better_supabase. Remove schema.",
      );
    }
    const mode = entry?.mode ?? "managed";
    const modes = module.modes ?? ["managed"];
    if (!modes.includes(mode)) {
      throw new TypeError(
        `sql.modules.${name}.mode: the ${name} module supports ${modes.join(", ")}, not ${mode}`,
      );
    }
  }
  for (const use of migrationOptionUses(config)) {
    if (!use.adopted) {
      throw new TypeError(
        `${use.message} Only adopt mode accepts it: set sql.modules.${use.module}.mode to "adopt" while you migrate an existing schema, or remove the option.`,
      );
    }
  }
}
