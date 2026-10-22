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
  Bulk: "BulkActions",
  bulkBlock: "bulkActionsBlock",
  bulkEvents: "bulkActionsEvents",
  BulkEvents: "BulkActionsEvents",
  BulkOptions: "BulkActionsOptions",
  Controls: "Compliance",
  controlsBlock: "complianceBlock",
  controlsEvents: "complianceEvents",
  ControlsEvents: "ComplianceEvents",
  ControlsOptions: "ComplianceOptions",
  createAccess: "createPermissions",
  createActivity: "createTimeline",
  createAiProviders: "createAiKeys",
  createAiTasks: "createAiSchedules",
  createBulk: "createBulkActions",
  createControls: "createCompliance",
  createEngagements: "createActivities",
  createFlags: "createFeatureFlags",
  createFlagsProvider: "createFeatureFlagsProvider",
  createIdentities: "createLinkedIdentities",
  createJobs: "createQueue",
  createNumberSequences: "createNumbering",
  createParties: "createContacts",
  createPasses: "createAdmissionPasses",
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
  Flags: "FeatureFlags",
  flagsBlock: "featureFlagsBlock",
  flagsEvents: "featureFlagsEvents",
  FlagsEvents: "FeatureFlagsEvents",
  FlagsOptions: "FeatureFlagsOptions",
  FlagsProvider: "FeatureFlagsProvider",
  FlagsProviderOptions: "FeatureFlagsProviderOptions",
  Identities: "LinkedIdentities",
  identitiesBlock: "linkedIdentitiesBlock",
  IdentitiesOptions: "LinkedIdentitiesOptions",
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
  Passes: "AdmissionPasses",
  passesBlock: "admissionPassesBlock",
  passesEvents: "admissionPassesEvents",
  PassesEvents: "AdmissionPassesEvents",
  PassesOptions: "AdmissionPassesOptions",
  passesSection: "admissionPassesSection",
  passesSqlOptions: "admissionPassesSqlOptions",
  PassesSqlOptions: "AdmissionPassesSqlOptions",
  PassesWrites: "AdmissionPassesWrites",
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
  sessionsBlock: "sessionRevocationBlock",
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

      return to === undefined
        ? specifier
        : `${quote}better-supabase/${to}${quote}`;
    },
  );
}
