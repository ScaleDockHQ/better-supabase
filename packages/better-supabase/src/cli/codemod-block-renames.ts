/**
 * The 0.15 block renames in app code: the exports named after a block and the
 * `better-supabase/blocks/<name>` subpaths.
 */

import { BLOCK_RENAMES } from "../sql/index.ts";

/** Exports named after a renamed block: the 0.14 name, then the 0.15 one. */
export const BLOCK_EXPORT_RENAMES: Readonly<Record<string, string>> = {
  Access: "Permissions",
  accessBlock: "permissionsBlock",
  AccessOptions: "PermissionsOptions",
  Activity: "Timeline",
  activityBlock: "timelineBlock",
  ActivityOptions: "TimelineOptions",
  AiProviders: "AiKeys",
  aiProvidersBlock: "aiKeysBlock",
  aiProvidersEvents: "aiKeysEvents",
  AiProvidersEvents: "AiKeysEvents",
  AiProvidersOptions: "AiKeysOptions",
  AiTasks: "AiSchedules",
  aiTasksBlock: "aiSchedulesBlock",
  AiTasksOptions: "AiSchedulesOptions",
  Controls: "Compliance",
  controlsBlock: "complianceBlock",
  controlsEvents: "complianceEvents",
  ControlsEvents: "ComplianceEvents",
  ControlsOptions: "ComplianceOptions",
  createAccess: "createPermissions",
  createActivity: "createTimeline",
  createAiProviders: "createAiKeys",
  createAiTasks: "createAiSchedules",
  createControls: "createCompliance",
  createEngagements: "createActivities",
  createJobs: "createQueue",
  createNumberSequences: "createNumbering",
  createParties: "createContacts",
  createRules: "createAutomations",
  createRulesAdmin: "createAutomationsAdmin",
  createServicePrincipals: "createServiceAccounts",
  createSharedSignals: "createSecurityEvents",
  createTargets: "createGoals",
  createWorkflowBuilder: "createWorkflowEditor",
  createWorkflowBuilderController: "createWorkflowEditorController",
  createWorkItems: "createTasks",
  Engagements: "Activities",
  engagementsBlock: "activitiesBlock",
  engagementsEvents: "activitiesEvents",
  EngagementsEvents: "ActivitiesEvents",
  EngagementsOptions: "ActivitiesOptions",
  Jobs: "Queue",
  jobsBlock: "queueBlock",
  JobsOptions: "QueueOptions",
  NumberSequences: "Numbering",
  numberSequencesBlock: "numberingBlock",
  numberSequencesEvents: "numberingEvents",
  NumberSequencesEvents: "NumberingEvents",
  NumberSequencesOptions: "NumberingOptions",
  Parties: "Contacts",
  partiesBlock: "contactsBlock",
  partiesEvents: "contactsEvents",
  PartiesEvents: "ContactsEvents",
  PartiesOptions: "ContactsOptions",
  Rules: "Automations",
  RulesAdmin: "AutomationsAdmin",
  rulesBlock: "automationsBlock",
  rulesEvents: "automationsEvents",
  RulesEvents: "AutomationsEvents",
  RulesOptions: "AutomationsOptions",
  ServicePrincipals: "ServiceAccounts",
  servicePrincipalsBlock: "serviceAccountsBlock",
  servicePrincipalsEvents: "serviceAccountsEvents",
  ServicePrincipalsEvents: "ServiceAccountsEvents",
  ServicePrincipalsOptions: "ServiceAccountsOptions",
  SharedSignals: "SecurityEvents",
  sharedSignalsBlock: "securityEventsBlock",
  sharedSignalsEvents: "securityEventsEvents",
  SharedSignalsEvents: "SecurityEventsEvents",
  SharedSignalsOptions: "SecurityEventsOptions",
  supportSessionsEvents: "impersonationEvents",
  SupportSessionsEvents: "ImpersonationEvents",
  Targets: "Goals",
  targetsBlock: "goalsBlock",
  TargetsOptions: "GoalsOptions",
  useWorkflowBuilder: "useWorkflowEditor",
  UseWorkflowBuilderOptions: "UseWorkflowEditorOptions",
  WorkflowBuilder: "WorkflowEditor",
  WorkflowBuilderActions: "WorkflowEditorActions",
  workflowBuilderBlock: "workflowEditorBlock",
  WorkflowBuilderController: "WorkflowEditorController",
  WorkflowBuilderControllerOptions: "WorkflowEditorControllerOptions",
  workflowBuilderEvents: "workflowEditorEvents",
  WorkflowBuilderEvents: "WorkflowEditorEvents",
  WorkflowBuilderSnapshot: "WorkflowEditorSnapshot",
  WorkflowBuilderState: "WorkflowEditorState",
  WorkItems: "Tasks",
  workItemsBlock: "tasksBlock",
  workItemsEvents: "tasksEvents",
  WorkItemsEvents: "TasksEvents",
  WorkItemsOptions: "TasksOptions",
};

const FRAMEWORKS = ["", "/react", "/solid", "/svelte", "/vue"] as const;

/** `blocks/<name>` subpaths of renamed blocks, with their framework entries. */
export const BLOCK_SUBPATH_RENAMES: Readonly<Record<string, string>> =
  Object.fromEntries(
    Object.entries(BLOCK_RENAMES).flatMap(([from, to]) =>
      FRAMEWORKS.map((suffix): [string, string] => [
        `blocks/${from}${suffix}`,
        `blocks/${to}${suffix}`,
      ]),
    ),
  );

/**
 * The names the built-in plugins' subpaths exported, renamed to the block
 * extensions, guards and validation that replace them.
 */
export const PLUGIN_IMPORT_RENAMES: Readonly<
  Record<string, Readonly<Record<string, string>>>
> = {
  "plugins/tenant": {
    tenant: "membershipsExtension",
    TenantOptions: "MembershipsExtensionOptions",
    TenantFindArgs: "MembershipsFindArgs",
    TenantExtension: "MembershipsExtension",
    resolveTenant: "resolveOrganization",
  },
  "plugins/actor": {
    actor: "createdByExtension",
    ActorOptions: "CreatedByExtensionOptions",
  },
  "plugins/timestamps": { timestamps: "updatedAtExtension" },
  "plugins/soft-delete": {
    softDelete: "trashExtension",
    SoftDeleteFindArgs: "TrashFindArgs",
    SoftDeleteDeleteArgs: "TrashDeleteArgs",
    SoftDeleteMethods: "TrashMethods",
    SoftDeleteExtension: "TrashExtension",
  },
  "plugins/rules": {
    rules: "guards",
    safe: "safeGuards",
    recommended: "recommendedGuards",
    strict: "strictGuards",
    RuleSet: "GuardSet",
    RuleSetting: "GuardSetting",
    RuleLevel: "GuardLevel",
    RuleName: "GuardName",
    RuleViolation: "GuardViolation",
    AutomationsOptions: "GuardsOptions",
    RulesFindArgs: "GuardsFindArgs",
    RulesExtension: "GuardsExtension",
  },
};

/** The built-in plugins' subpaths; `""` is the package root. */
export const PLUGIN_SUBPATH_RENAMES: Readonly<Record<string, string>> = {
  "plugins/tenant": "blocks/memberships",
  "plugins/actor": "blocks/created-by",
  "plugins/timestamps": "blocks/updated-at",
  "plugins/soft-delete": "blocks/trash",
  "plugins/rules": "lint",
  "plugins/validation": "",
};

/**
 * The renderer subpaths `better-supabase/spec` now exports, with the same
 * names.
 */
export const SPEC_SUBPATH_RENAMES: Readonly<Record<string, string>> = {
  openapi: "spec",
  asyncapi: "spec",
  arazzo: "spec",
  overlay: "spec",
};

/** Every subpath the 0.15 codemod rewrites. */
export const SUBPATH_RENAMES_0_15: Readonly<Record<string, string>> = {
  ...BLOCK_SUBPATH_RENAMES,
  ...PLUGIN_SUBPATH_RENAMES,
  ...SPEC_SUBPATH_RENAMES,
};

/** The 0.15 codemod's review hints: names and calls it can't rewrite safely. */
export const REVIEW_0_15: readonly {
  readonly pattern: RegExp;
  readonly message: string;
}[] = [
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
    pattern: /\bbsBlock\b|\bboth provide the\b/,
    message:
      "Block queries share the table key space `['bsb', instance, method, ...args]` and carry `meta.bsTables: [instance]` instead of `bsBlock`; two blocks may provide one port, and a consumer picks one with `blocks.<instance>.uses` or `createBlocks({ ports })`",
  },
  {
    pattern:
      /\b(?:sectionAction|recordServer|defineRecordFeature)\b|supabase\/features\/|(?:navigation|commands)\.generated/,
    message:
      "Record features are record types: import `<type>Record` from `@/lib/supabase/records/<type>`, call `bsb.record(<type>Record)` for `load`, `timeline`, `actions` and `tags` instead of `recordServer` and `bsb.sectionAction`, and read `bindings` instead of `sections`; `gen` no longer writes the features folder, `navigation.generated.ts` or `commands.generated.ts`",
  },
  {
    pattern: /["'`]bs:t:/,
    message: "Realtime change topics are `bsb:t:<schema>.<table>`",
  },
  {
    pattern:
      /["'`]better-supabase\/(?:work-items|parties|engagements|targets|number-sequences|actor|ensure-rls|shared-signals|service-principals|support-sessions|controls|ai-tasks|ai-providers|workflow-builder|jobs|access|rules|tenant|activity|workflow-sdk-world)[./"'`]/,
    message:
      "Event sources are `better-supabase/<block>` under the 0.15 block name (`better-supabase/tasks`, not `better-supabase/work-items`); update CloudEvent source filters",
  },
  {
    pattern: /\bmembershipsExtension\s*\(/,
    message:
      'The generated schema installs `membershipsExtension` with `auth.tenant`\'s settings, and its `onMissing` default is now `skip`: keep this `.use()` only for a custom `resolve`, and pass `onMissing: "error"` to keep the 0.14 behavior',
  },
  {
    pattern:
      /\b(?:updatedAtExtension|createdByExtension|trashExtension|validation)\s*\(/,
    message:
      "The generated schema installs the installed blocks' extensions and `validation` (when a generator writes validators): this `.use()` replaces that one and can go unless it passes options",
  },
  {
    pattern: /\.(?:forSubject|untag)\s*\(|\btags\.(?:tag|create)\s*\(/,
    message:
      "Block clients use the data verbs: `tags.tag` and `untag` are `attach` and `detach`, `tags.create` takes `{ kind, name, color?, description?, fields? }`, `tags.update` takes `{ name?, fields? }`, `tags.list` takes `{ kind?, on? }`, and `forSubject(record)` on tags, channels and scores is `list({ on: record })`",
  },
  {
    pattern: /\.(?:save|set)\s*\(/,
    message:
      "A block client's `save` is `upsert` (segments, courses, memory, automations, workflow-editor, ai-chat sessions, sequences, flags, reminders, templates, saved-views, ai-keys, calendar, goals, pipelines, connector sessions), and so are `set` on ai-cache and on ai-files `providerFiles`; editor controllers and settings keep their verbs",
  },
  {
    pattern:
      /\b(?:fileMaintenance|updateMaintenance|listMaintenance|maintenanceRequestInputSchema)\b|maintenance_request\.(?:filed|updated)/,
    message:
      'Leases no longer tracks maintenance requests: install a tasks instance (`maintenance: { block: "tasks", names: { work_item: "maintenance_request" } }`) and call its client; the upgrade renames the old table to `maintenance_requests_legacy`',
  },
  {
    pattern: /\bpass_credit_entries\b/,
    message:
      "Class credits live on the ledger: read them with `credits(passId)` or the ledger client instead of `pass_credit_entries`",
  },
  {
    pattern: /limit: 1 \}\)\.map\(\(rows\) => rows\[0\] \?\? null\)/,
    message:
      "This was `findFirst`. Read sets and query specs have no `.map`: there, use `get({ where }, { optional: true })` when the filter matches one row, or destructure the first row of `list({ limit: 1 })`",
  },
];

const SPECIFIER = /(["'])better-supabase\/([\w./-]+)\1/g;

/** `text` with each `better-supabase/<subpath>` specifier in `renames` renamed. */
export function renameSubpaths(
  text: string,
  renames: Readonly<Record<string, string>>,
): string {
  return text.replaceAll(
    SPECIFIER,
    (specifier, quote: string, subpath: string) => {
      const to = Object.hasOwn(renames, subpath) ? renames[subpath] : undefined;

      if (to === undefined) {
        return specifier;
      }

      return to === ""
        ? `${quote}better-supabase${quote}`
        : `${quote}better-supabase/${to}${quote}`;
    },
  );
}
