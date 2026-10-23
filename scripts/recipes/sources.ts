import type { RecipeSource } from "./types.ts";

import { OPERATIONS_RECIPES } from "./operations.ts";
/**
 * The recipe list that `build-recipes.ts` renders. A recipe with a `web` side
 * is available; the planned ones in `planned.ts` name what they wait for.
 */
import { PLANNED } from "./planned.ts";
import { RECORD_RECIPES } from "./records.ts";
import { SAAS_RECIPES } from "./saas.ts";
import { NATIVE_APP, WEB_APP } from "./types.ts";

export const RECIPES: readonly RecipeSource[] = [
  {
    slug: "notification-bell",
    title: "Notification bell",
    blocks: ["notifications"],
    kind: "component",
    description:
      "A header button with the unread count, which updates when a notification arrives or is read.",
    hook: { name: "useNotifications", entry: "@/hooks/use-notifications" },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/unread-badge.tsx`,
      components: ["badge", "button"],
      glue: ["use-notifications", "notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-bell.tsx`,
      components: ["Pressable", "Text", "View"],
      glue: ["use-notifications", "blocks"],
    },
  },
  {
    slug: "notification-list",
    title: "Notification list",
    blocks: ["notifications"],
    kind: "component",
    description:
      "The caller's latest notifications with an unread marker, loaded again on every change.",
    hook: { name: "useNotifications", entry: "@/hooks/use-notifications" },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/notification-list.tsx`,
      components: ["badge", "empty", "skeleton"],
      glue: ["use-notifications", "notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-list.tsx`,
      components: ["ActivityIndicator", "FlatList", "Text", "View"],
      glue: ["use-notifications", "blocks"],
    },
  },
  {
    slug: "command-search",
    title: "Command search",
    blocks: ["search"],
    kind: "component",
    description:
      "A search dialog over the search index, with favorites and recents before the user types.",
    hook: { name: "useCommandSearch", entry: "@/hooks/use-search" },
    web: {
      file: `${WEB_APP}/src/features/search/components/command-search.tsx`,
      components: ["button", "dialog", "input"],
      glue: ["use-search"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/command-search.tsx`,
      components: [
        "Modal",
        "Pressable",
        "SectionList",
        "Text",
        "TextInput",
        "View",
      ],
      glue: ["use-search"],
    },
  },
  {
    slug: "onboarding-checklist",
    title: "Onboarding checklist",
    blocks: ["onboarding"],
    kind: "component",
    description:
      "The organization's getting-started steps with progress, hidden once every step is done.",
    hook: { name: "useOnboarding", entry: "@/hooks/use-onboarding" },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/onboarding-card.tsx`,
      components: ["button", "card", "progress", "skeleton"],
      glue: ["use-onboarding", "onboarding-checklist"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/onboarding-checklist.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: ["use-onboarding", "onboarding-checklist"],
    },
  },
  {
    slug: "comment-thread",
    title: "Comment thread",
    blocks: ["comments"],
    kind: "component",
    description:
      "A record's comments with their authors and a form to add one, kept current after each write.",
    hook: { name: "useComments", entry: "@/hooks/use-comments" },
    web: {
      file: `${WEB_APP}/src/features/customers/components/comment-thread.tsx`,
      components: ["button", "field", "skeleton", "textarea"],
      glue: ["use-comments"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/comment-thread.tsx`,
      components: [
        "ActivityIndicator",
        "Button",
        "FlatList",
        "Text",
        "TextInput",
        "View",
      ],
      glue: ["use-comments"],
    },
  },
  {
    slug: "org-switcher",
    title: "Organization switcher",
    blocks: ["organizations"],
    kind: "component",
    description:
      "A menu of the user's organizations that switches the active one and refreshes the session for its tenant claim.",
    hook: { name: "useOrganizations", entry: "@/hooks/use-organizations" },
    web: {
      file: `${WEB_APP}/src/features/organization/components/organization-switcher-menu.tsx`,
      components: ["dropdown-menu", "sidebar"],
      glue: ["use-organizations"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/organization-switcher.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: ["use-organizations"],
    },
  },
  {
    slug: "plan-picker",
    title: "Plan picker",
    blocks: ["billing"],
    kind: "component",
    description:
      "The plans with their prices and a checkout button each. Checkout starts in a server action or API route that holds the Stripe key, and the client opens the URL it returns.",
    hook: { name: "usePlanPicker", entry: "@/hooks/use-billing" },
    web: {
      file: `${WEB_APP}/src/features/billing/components/plan-picker.tsx`,
      components: ["button", "card"],
      glue: ["use-billing"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/plan-picker.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: ["use-billing"],
    },
  },
  {
    slug: "usage-meter",
    title: "Usage meter",
    blocks: ["usage"],
    kind: "component",
    description:
      "This period's usage per meter against the plan's quota, with the reset date.",
    hook: { name: "useUsageMeter", entry: "@/hooks/use-usage" },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/usage-card.tsx`,
      components: ["card", "progress", "skeleton"],
      glue: ["use-usage"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/usage-meter.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: ["use-usage"],
    },
  },
  {
    slug: "feature-gate",
    title: "Feature gate",
    blocks: ["entitlements"],
    kind: "component",
    description:
      "Content shown only when the active organization's plan includes a feature, read from the session's features claim and updated when the session refreshes.",
    hook: { name: "useFeatureGate", entry: "@/hooks/use-entitlements" },
    web: {
      file: `${WEB_APP}/src/features/billing/components/feature-gate.tsx`,
      components: ["button", "skeleton"],
      glue: ["use-entitlements"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/feature-gate.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: ["use-entitlements"],
    },
  },
  {
    slug: "settings-layout",
    title: "Settings layout",
    blocks: ["settings"],
    kind: "screen",
    description:
      "Settings pages generated from the settings definition: a section per scope and a control per key, picked by the kind its schema declares.",
    hook: { name: "useSettings", entry: "@/hooks/use-settings" },
    web: {
      file: `${WEB_APP}/src/features/settings/components/settings-layout.tsx`,
      components: ["card", "field", "input", "select", "skeleton", "switch"],
      glue: ["use-settings"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/settings-layout.tsx`,
      components: [
        "ActivityIndicator",
        "Pressable",
        "ScrollView",
        "Switch",
        "Text",
        "TextInput",
        "View",
      ],
      glue: ["use-settings"],
    },
  },
  {
    slug: "members-table",
    title: "Members table",
    blocks: ["organizations"],
    kind: "component",
    description:
      "An organization's members with their roles, where a role change shows at once and a member can be removed.",
    hook: { name: "useMembers", entry: "@/hooks/use-organizations" },
    web: {
      file: `${WEB_APP}/src/features/organization/components/member-table.tsx`,
      components: ["avatar", "button", "select", "table"],
      glue: ["use-organizations"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/members-table.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: ["use-organizations"],
    },
  },
  {
    slug: "invite-dialog",
    title: "Invite dialog",
    blocks: ["invitations"],
    kind: "component",
    description:
      "A form that invites a teammate by email with a role, then shows the token for the accept link.",
    hook: { name: "useInvitations", entry: "@/hooks/use-organizations" },
    web: {
      file: `${WEB_APP}/src/features/organization/components/invite-member-dialog.tsx`,
      components: ["button", "dialog", "field", "input", "select"],
      glue: ["use-organizations"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/invite-dialog.tsx`,
      components: ["Button", "Modal", "Pressable", "Text", "TextInput", "View"],
      glue: ["use-organizations"],
    },
  },
  {
    slug: "api-keys-table",
    title: "API keys table",
    blocks: ["api-keys"],
    kind: "component",
    description:
      "The organization's API keys, with a form that creates one and shows its token once, and a revoke button per key.",
    hook: { name: "useApiKeys", entry: "@/hooks/use-api-keys" },
    web: {
      file: `${WEB_APP}/src/features/api-keys/components/api-key-table.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "dialog",
        "empty",
        "field",
        "input",
        "skeleton",
        "table",
      ],
      glue: ["use-api-keys"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/api-keys-table.tsx`,
      components: [
        "ActivityIndicator",
        "Button",
        "Pressable",
        "Text",
        "TextInput",
        "View",
      ],
      glue: ["use-api-keys"],
    },
  },
  {
    slug: "audit-log-table",
    title: "Audit log table",
    blocks: ["audit"],
    kind: "component",
    description:
      "The audit trail, newest first, with filters by actor and action and older pages on demand.",
    hook: { name: "useAuditLog", entry: "@/hooks/use-audit" },
    web: {
      file: `${WEB_APP}/src/features/audit/components/audit-log-table.tsx`,
      components: ["button", "select", "skeleton", "table"],
      glue: ["use-audit"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/audit-log-table.tsx`,
      components: ["ActivityIndicator", "Button", "Pressable", "Text", "View"],
      glue: ["use-audit"],
    },
  },
  {
    slug: "tag-input",
    title: "Tag input",
    blocks: ["tags"],
    kind: "component",
    description:
      "A record's tags with suggestions, where typing a name adds a tag or creates it.",
    hook: { name: "useTagInput", entry: "@/hooks/use-tags" },
    web: {
      file: `${WEB_APP}/src/features/customers/components/tag-input.tsx`,
      components: ["badge", "button", "input", "skeleton"],
      glue: ["use-tags"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/tag-input.tsx`,
      components: [
        "ActivityIndicator",
        "Button",
        "Pressable",
        "Text",
        "TextInput",
        "View",
      ],
      glue: ["use-tags"],
    },
  },
  {
    slug: "announcement-banner",
    title: "Announcement banner",
    blocks: ["announcements"],
    kind: "component",
    description:
      "The newest live announcement for the user and organization, with a dismiss button.",
    hook: { name: "useAnnouncements", entry: "@/hooks/use-announcements" },
    web: {
      file: `${WEB_APP}/src/features/announcements/components/announcement-banner.tsx`,
      components: ["alert", "button"],
      glue: ["use-announcements"],
    },
  },
  {
    slug: "profile-form",
    title: "Profile form",
    blocks: ["profiles"],
    kind: "component",
    description:
      "A form that updates the caller's display name through a server action and shows field errors.",
    web: {
      file: `${WEB_APP}/src/features/user/components/profile-form.tsx`,
      components: ["button", "field", "input"],
      glue: [],
    },
  },
  {
    slug: "mfa-setup",
    title: "Two-factor setup",
    blocks: ["mfa"],
    kind: "component",
    description:
      "A card that enrolls an authenticator app with a QR code, verifies the first code and removes the factor.",
    web: {
      file: `${WEB_APP}/src/features/user/components/two-factor-card.tsx`,
      components: ["badge", "button", "card", "field", "input-otp"],
      glue: [],
    },
  },
  {
    slug: "inbox-threads",
    title: "Inbox with threads",
    blocks: ["inbox"],
    kind: "screen",
    description:
      "A shared inbox of conversations with status tabs, an assignee filter and the open thread beside the list.",
    hook: { name: "useInbox", entry: "@/hooks/use-inbox" },
    web: {
      file: `${WEB_APP}/src/features/inbox/components/inbox-view.tsx`,
      components: ["badge", "empty", "select", "tabs"],
      glue: ["use-inbox"],
    },
  },
  {
    slug: "channel-sidebar",
    title: "Channel sidebar",
    blocks: ["channels", "messaging"],
    kind: "component",
    description:
      "The caller's channels with unread and mention counts, kept live, with dialogs to browse, join and create channels.",
    hook: { name: "useConversations", entry: "@/hooks/use-messaging" },
    web: {
      file: `${WEB_APP}/src/features/chat/components/channel-sidebar.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "label",
        "scroll-area",
        "skeleton",
        "switch",
      ],
      glue: ["use-messaging"],
    },
  },
  {
    slug: "message-list",
    title: "Message list",
    blocks: ["messaging", "channels"],
    kind: "component",
    description:
      "A conversation's messages over Realtime, with older pages on demand, who is typing, reply counts and the composer.",
    hook: { name: "useMessages", entry: "@/hooks/use-messaging" },
    web: {
      file: `${WEB_APP}/src/features/chat/components/message-list.tsx`,
      components: [
        "alert",
        "button",
        "card",
        "empty",
        "scroll-area",
        "skeleton",
      ],
      glue: ["use-messaging"],
    },
  },
  {
    slug: "message-composer",
    title: "Message composer",
    blocks: ["messaging", "attachments"],
    kind: "component",
    description:
      "A message box that sends on Enter, signals typing, and uploads dropped, pasted or picked files onto the message.",
    web: {
      file: `${WEB_APP}/src/features/chat/components/message-composer.tsx`,
      components: ["badge", "button", "label", "spinner", "textarea"],
      glue: [],
    },
  },
  {
    slug: "thread-panel",
    title: "Thread panel",
    blocks: ["messaging", "channels"],
    kind: "component",
    description:
      "A thread beside the channel: the root message, its replies live over Realtime, and a composer that replies into it.",
    hook: { name: "useMessages", entry: "@/hooks/use-messaging" },
    web: {
      file: `${WEB_APP}/src/features/chat/components/thread-panel.tsx`,
      components: [
        "alert",
        "button",
        "card",
        "empty",
        "scroll-area",
        "separator",
        "skeleton",
      ],
      glue: ["use-messaging"],
    },
  },
  {
    slug: "presence-avatars",
    title: "Presence avatars",
    blocks: ["messaging"],
    kind: "component",
    description:
      "Who else has a record open (a channel, a comment thread's record or a document), on the record's presence topic.",
    hook: { name: "usePresence", entry: "better-supabase/react" },
    web: {
      file: `${WEB_APP}/src/features/chat/components/presence-avatars.tsx`,
      components: ["avatar"],
      glue: [],
    },
  },
  {
    slug: "workspace-url-field",
    title: "Workspace URL field",
    blocks: ["organizations", "reserved-slugs"],
    kind: "component",
    description:
      "An organization form with a name and a URL slug, where reserved and taken slugs come back as field errors.",
    web: {
      file: `${WEB_APP}/src/features/organization/components/organization-form.tsx`,
      components: ["button", "field", "input"],
      glue: [],
    },
  },
  {
    slug: "chat-with-history",
    title: "Chat with history",
    blocks: ["ai-chat"],
    kind: "screen",
    description:
      "An AI chat that stores every message, resumes a stored conversation and streams the reply.",
    hook: { name: "useAssistant", entry: "better-supabase/ai-sdk/react" },
    web: {
      file: `${WEB_APP}/src/features/assistant/components/assistant-chat.tsx`,
      components: ["button", "textarea"],
      glue: [],
    },
  },
  {
    slug: "knowledge-upload",
    title: "Knowledge base upload",
    blocks: ["knowledge"],
    kind: "component",
    description:
      "A form that adds a document to the knowledge base, which chunks and embeds it for search.",
    web: {
      file: `${WEB_APP}/src/features/knowledge/components/add-document-form.tsx`,
      components: ["button", "field", "input", "textarea"],
      glue: [],
    },
  },
  {
    slug: "agent-run-trace",
    title: "Agent activity",
    blocks: ["agents"],
    kind: "component",
    description:
      "The agent runs for the organization with their steps and the approvals that wait for a person.",
    web: {
      file: `${WEB_APP}/src/features/assistant/components/agent-activity.tsx`,
      components: ["badge", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "workflow-canvas",
    title: "Workflow canvas",
    blocks: ["workflow-editor", "workflows"],
    kind: "screen",
    description:
      "A node editor for a workflow definition that saves drafts, publishes versions and runs the workflow.",
    hook: {
      name: "useWorkflowCanvasRun",
      entry: "@/hooks/use-workflow-editor",
    },
    web: {
      file: `${WEB_APP}/src/features/workflows/builder/components/workflow-canvas.tsx`,
      components: ["badge", "button", "input", "select"],
      glue: ["use-workflow-editor"],
    },
  },
  {
    slug: "workflow-runs",
    title: "Workflow runs",
    blocks: ["workflows"],
    kind: "component",
    description:
      "The latest workflow runs with their status, which update while a run is in progress.",
    hook: { name: "useWorkflowRuns", entry: "@/hooks/use-workflows" },
    web: {
      file: `${WEB_APP}/src/features/workflows/components/workflow-runs.tsx`,
      components: ["badge", "empty", "skeleton", "table"],
      glue: ["use-workflows"],
    },
  },
  {
    slug: "connector-setup",
    title: "Connector credentials",
    blocks: ["connectors", "credentials"],
    kind: "component",
    description:
      "A sheet that stores a connector credential encrypted and revokes it, without reading the secret back.",
    web: {
      file: `${WEB_APP}/src/features/workflows/builder/components/credential-sheet.tsx`,
      components: ["button", "field", "input", "sheet"],
      glue: [],
    },
  },
  {
    slug: "support-session-banner",
    title: "Support session banner",
    blocks: ["impersonation"],
    kind: "component",
    description:
      "A banner that tells the user a support agent is viewing the app as them, rendered on the server.",
    web: {
      file: `${WEB_APP}/src/features/user/components/impersonation-banner.tsx`,
      components: ["alert"],
      glue: [],
    },
  },
  {
    slug: "ai-task-queue",
    title: "AI task queue",
    blocks: ["ai-schedules"],
    kind: "component",
    description:
      "A table of scheduled AI prompts with each task's next run and latest run status, plus pause and resume.",
    web: {
      file: `${WEB_APP}/src/features/ai-tasks/components/ai-task-queue.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "card",
        "empty",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "ai-provider-settings",
    title: "AI provider settings",
    blocks: ["ai-keys"],
    kind: "component",
    description:
      "A settings card that lists the organization's own AI provider keys and models, adds a key to Vault and removes one.",
    web: {
      file: `${WEB_APP}/src/features/ai-providers/components/ai-provider-settings.tsx`,
      components: [
        "alert",
        "alert-dialog",
        "badge",
        "button",
        "card",
        "dialog",
        "empty",
        "field",
        "input",
        "select",
        "skeleton",
        "table",
      ],
      glue: [],
    },
  },
  {
    slug: "push-opt-in",
    title: "Push opt-in",
    blocks: ["push"],
    kind: "component",
    description:
      "A card that registers this browser for web push and removes it again.",
    web: {
      file: `${WEB_APP}/src/features/push/components/push-opt-in.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "metrics-dashboard",
    title: "Metrics dashboard",
    blocks: ["metrics"],
    kind: "screen",
    description:
      "A card per metric: the 30-day total against the 30 days before, with daily bars.",
    web: {
      file: `${WEB_APP}/src/features/metrics/components/metrics-dashboard.tsx`,
      components: ["alert", "badge", "button", "card", "empty", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "feature-flag-toggles",
    title: "Feature flags",
    blocks: ["flags"],
    kind: "component",
    description:
      "Which feature flags are on for the active organization, read-only.",
    web: {
      file: `${WEB_APP}/src/features/flags/components/feature-flag-list.tsx`,
      components: ["alert", "badge", "button", "card", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "rule-builder",
    title: "Rule builder",
    blocks: ["automations"],
    kind: "component",
    description:
      "A condition tree with field, operator and value rows, nested And and Or groups, drag to reorder and a fixed first condition, saved as a versioned rule.",
    hook: { name: "useRuleBuilder", entry: "@/hooks/use-automations" },
    web: {
      file: `${WEB_APP}/src/features/rules/components/rule-builder.tsx`,
      components: [
        "alert",
        "button",
        "card",
        "empty",
        "field",
        "input",
        "label",
        "select",
        "skeleton",
        "switch",
      ],
      glue: ["use-automations"],
    },
  },
  {
    slug: "can",
    title: "Can",
    blocks: ["permissions"],
    kind: "component",
    description:
      "Shows an action only to members who hold a permission key; the checks of one render share one round trip.",
    web: {
      file: `${WEB_APP}/src/features/projects/components/task-import-action.tsx`,
      components: [],
      glue: [],
    },
  },
  {
    slug: "subject-link",
    title: "Subject link",
    blocks: ["subjects"],
    kind: "component",
    description:
      "A link to any subject type, titled and routed by subject_titles, with plain text for a record the caller can't read.",
    hook: { name: "useSubject", entry: "@/hooks/use-subjects" },
    web: {
      file: `${WEB_APP}/src/features/subjects/components/subject-link.tsx`,
      components: ["button", "skeleton"],
      glue: ["use-subjects"],
    },
  },
  {
    slug: "subject-chip",
    title: "Subject chip",
    blocks: ["subjects"],
    kind: "component",
    description:
      "A compact badge with a subject's type and title that links to its page.",
    hook: { name: "useSubject", entry: "@/hooks/use-subjects" },
    web: {
      file: `${WEB_APP}/src/features/subjects/components/subject-chip.tsx`,
      components: ["skeleton"],
      glue: ["use-subjects"],
    },
  },
  ...SAAS_RECIPES,
  ...OPERATIONS_RECIPES,
  ...RECORD_RECIPES,
  ...PLANNED,
];
