/**
 * The recipe list that `build-recipes.ts` renders. A recipe with a `web` side
 * is available; the planned ones in `planned.ts` name what they wait for.
 */
import { PLANNED } from "./planned.ts";

export const WEB_APP = "apps/examples/nextjs";
export const NATIVE_APP = "apps/examples/expo-powersync";

export interface Side {
  /** The example file, relative to the repo root. */
  readonly file: string;
  /** Web: shadcn components (`npx shadcn add ...`). Native: React Native primitives. */
  readonly components: readonly string[];
  /** `@better-supabase/<item>` registry items the snippet imports. */
  readonly glue: readonly string[];
}

/** A piece of UI inside a page, or a whole page. */
export type RecipeKind = "component" | "screen";

export interface RecipeSource {
  readonly slug: string;
  readonly title: string;
  /** The SQL modules the recipe uses. The first one sets its category. */
  readonly blocks: readonly [string, ...string[]];
  readonly kind: RecipeKind;
  readonly description: string;
  /** The hook the code calls, and the entry it comes from. Server-rendered recipes have none. */
  readonly hook?: { readonly name: string; readonly entry: string };
  /** A recipe is available once its web side exists; native is optional. */
  readonly web?: Side;
  readonly native?: Side;
  /** For a planned recipe: what has to ship first. */
  readonly missing?: string;
}

export const RECIPES: readonly RecipeSource[] = [
  {
    slug: "notification-bell",
    title: "Notification bell",
    blocks: ["notifications"],
    kind: "component",
    description:
      "A header button with the unread count, which updates when a notification arrives or is read.",
    hook: {
      name: "useNotifications",
      entry: "better-supabase/blocks/notifications/react",
    },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/unread-badge.tsx`,
      components: ["badge", "button"],
      glue: ["notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-bell.tsx`,
      components: ["Pressable", "Text", "View"],
      glue: ["blocks"],
    },
  },
  {
    slug: "notification-list",
    title: "Notification list",
    blocks: ["notifications"],
    kind: "component",
    description:
      "The caller's latest notifications with an unread marker, loaded again on every change.",
    hook: {
      name: "useNotifications",
      entry: "better-supabase/blocks/notifications/react",
    },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/notification-list.tsx`,
      components: ["badge", "empty", "skeleton"],
      glue: ["notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-list.tsx`,
      components: ["ActivityIndicator", "FlatList", "Text", "View"],
      glue: ["blocks"],
    },
  },
  {
    slug: "command-search",
    title: "Command search",
    blocks: ["search"],
    kind: "component",
    description:
      "A search dialog over the search index, with favorites and recents before the user types.",
    hook: {
      name: "useCommandSearch",
      entry: "better-supabase/blocks/search/react",
    },
    web: {
      file: `${WEB_APP}/src/features/search/components/command-search.tsx`,
      components: ["button", "dialog", "input"],
      glue: [],
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
      glue: [],
    },
  },
  {
    slug: "onboarding-checklist",
    title: "Onboarding checklist",
    blocks: ["onboarding"],
    kind: "component",
    description:
      "The organization's getting-started steps with progress, hidden once every step is done.",
    hook: {
      name: "useOnboarding",
      entry: "better-supabase/blocks/onboarding/react",
    },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/onboarding-card.tsx`,
      components: ["button", "card", "progress", "skeleton"],
      glue: ["onboarding-checklist"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/onboarding-checklist.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: ["onboarding-checklist"],
    },
  },
  {
    slug: "comment-thread",
    title: "Comment thread",
    blocks: ["comments"],
    kind: "component",
    description:
      "A record's comments with their authors and a form to add one, kept current after each write.",
    hook: {
      name: "useComments",
      entry: "better-supabase/blocks/comments/react",
    },
    web: {
      file: `${WEB_APP}/src/features/customers/components/comment-thread.tsx`,
      components: ["button", "field", "skeleton", "textarea"],
      glue: [],
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
      glue: [],
    },
  },
  {
    slug: "org-switcher",
    title: "Organization switcher",
    blocks: ["organizations"],
    kind: "component",
    description:
      "A menu of the user's organizations that switches the active one and refreshes the session for its tenant claim.",
    hook: {
      name: "useOrganizations",
      entry: "better-supabase/blocks/organizations/react",
    },
    web: {
      file: `${WEB_APP}/src/features/organization/components/organization-switcher-menu.tsx`,
      components: ["dropdown-menu", "sidebar"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/organization-switcher.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "plan-picker",
    title: "Plan picker",
    blocks: ["billing"],
    kind: "component",
    description:
      "The plans with their prices and a checkout button each. Checkout starts in a server action or API route that holds the Stripe key, and the client opens the URL it returns.",
    hook: {
      name: "usePlanPicker",
      entry: "better-supabase/blocks/billing/react",
    },
    web: {
      file: `${WEB_APP}/src/features/billing/components/plan-picker.tsx`,
      components: ["button", "card"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/plan-picker.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "usage-meter",
    title: "Usage meter",
    blocks: ["usage"],
    kind: "component",
    description:
      "This period's usage per meter against the plan's quota, with the reset date.",
    hook: {
      name: "useUsageMeter",
      entry: "better-supabase/blocks/usage/react",
    },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/usage-card.tsx`,
      components: ["card", "progress", "skeleton"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/usage-meter.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "feature-gate",
    title: "Feature gate",
    blocks: ["entitlements"],
    kind: "component",
    description:
      "Content shown only when the active organization's plan includes a feature, read from the session's features claim and updated when the session refreshes.",
    hook: {
      name: "useFeatureGate",
      entry: "better-supabase/blocks/entitlements/react",
    },
    web: {
      file: `${WEB_APP}/src/features/billing/components/feature-gate.tsx`,
      components: ["button", "skeleton"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/feature-gate.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "settings-layout",
    title: "Settings layout",
    blocks: ["settings"],
    kind: "screen",
    description:
      "Settings pages generated from the settings definition: a section per scope and a control per key, picked by the kind its schema declares.",
    hook: {
      name: "useSettings",
      entry: "better-supabase/blocks/settings/react",
    },
    web: {
      file: `${WEB_APP}/src/features/settings/components/settings-layout.tsx`,
      components: ["card", "field", "input", "select", "skeleton", "switch"],
      glue: [],
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
      glue: [],
    },
  },
  {
    slug: "members-table",
    title: "Members table",
    blocks: ["organizations"],
    kind: "component",
    description:
      "An organization's members with their roles, where a role change shows at once and a member can be removed.",
    hook: {
      name: "useMembers",
      entry: "better-supabase/blocks/organizations/react",
    },
    web: {
      file: `${WEB_APP}/src/features/organization/components/member-table.tsx`,
      components: ["avatar", "button", "select", "table"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/members-table.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "invite-dialog",
    title: "Invite dialog",
    blocks: ["invitations"],
    kind: "component",
    description:
      "A form that invites a teammate by email with a role, then shows the token for the accept link.",
    hook: {
      name: "useInvitations",
      entry: "better-supabase/blocks/organizations/react",
    },
    web: {
      file: `${WEB_APP}/src/features/organization/components/invite-member-dialog.tsx`,
      components: ["button", "dialog", "field", "input", "select"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/invite-dialog.tsx`,
      components: ["Button", "Modal", "Pressable", "Text", "TextInput", "View"],
      glue: [],
    },
  },
  {
    slug: "api-keys-table",
    title: "API keys table",
    blocks: ["api-keys"],
    kind: "component",
    description:
      "The organization's API keys, with a form that creates one and shows its token once, and a revoke button per key.",
    hook: {
      name: "useApiKeys",
      entry: "better-supabase/blocks/api-keys/react",
    },
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
      glue: [],
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
      glue: [],
    },
  },
  {
    slug: "audit-log-table",
    title: "Audit log table",
    blocks: ["audit"],
    kind: "component",
    description:
      "The audit trail, newest first, with filters by actor and action and older pages on demand.",
    hook: {
      name: "useAuditLog",
      entry: "better-supabase/blocks/audit/react",
    },
    web: {
      file: `${WEB_APP}/src/features/audit/components/audit-log-table.tsx`,
      components: ["button", "select", "skeleton", "table"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/audit-log-table.tsx`,
      components: ["ActivityIndicator", "Button", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "tag-input",
    title: "Tag input",
    blocks: ["tags"],
    kind: "component",
    description:
      "A record's tags with suggestions, where typing a name adds a tag or creates it.",
    hook: {
      name: "useTagInput",
      entry: "better-supabase/blocks/tags/react",
    },
    web: {
      file: `${WEB_APP}/src/features/customers/components/tag-input.tsx`,
      components: ["badge", "button", "input", "skeleton"],
      glue: [],
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
      glue: [],
    },
  },
  {
    slug: "announcement-banner",
    title: "Announcement banner",
    blocks: ["announcements"],
    kind: "component",
    description:
      "The newest live announcement for the user and organization, with a dismiss button.",
    hook: {
      name: "useAnnouncements",
      entry: "better-supabase/blocks/announcements/react",
    },
    web: {
      file: `${WEB_APP}/src/features/announcements/components/announcement-banner.tsx`,
      components: ["alert", "button"],
      glue: [],
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
    hook: { name: "useInbox", entry: "better-supabase/blocks/inbox/react" },
    web: {
      file: `${WEB_APP}/src/features/inbox/components/inbox-view.tsx`,
      components: ["badge", "empty", "select", "tabs"],
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
    blocks: ["workflow-builder", "workflows"],
    kind: "screen",
    description:
      "A node editor for a workflow definition that saves drafts, publishes versions and runs the workflow.",
    hook: {
      name: "useWorkflowCanvasRun",
      entry: "better-supabase/blocks/workflow-builder/react",
    },
    web: {
      file: `${WEB_APP}/src/features/workflows/builder/components/workflow-canvas.tsx`,
      components: ["badge", "button", "input", "select"],
      glue: [],
    },
  },
  {
    slug: "workflow-runs",
    title: "Workflow runs",
    blocks: ["workflows"],
    kind: "component",
    description:
      "The latest workflow runs with their status, which update while a run is in progress.",
    hook: {
      name: "useWorkflowRuns",
      entry: "better-supabase/blocks/workflows/react",
    },
    web: {
      file: `${WEB_APP}/src/features/workflows/components/workflow-runs.tsx`,
      components: ["badge", "empty", "skeleton", "table"],
      glue: [],
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
    blocks: ["support-sessions"],
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
    blocks: ["ai-tasks"],
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
    blocks: ["ai-providers"],
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
  ...PLANNED,
];
