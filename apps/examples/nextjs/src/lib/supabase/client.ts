import { createClient } from "better-supabase/client";

import { publicEnv as env } from "@/env-public";

import {
  announcementsConfig,
  apiKeysConfig,
  attachmentsConfig,
  auditConfig,
  automationsConfig,
  commentsConfig,
  entitlementsConfig,
  inboxConfig,
  messagingConfig,
  notificationsConfig,
  onboardingConfig,
  organizationsConfig,
  permissionsConfig,
  reactionsConfig,
  searchConfig,
  sessionsConfig,
  settingsConfig,
  subjectsConfig,
  tagsConfig,
  usageConfig,
  workflowEditorConfig,
  workflowsConfig,
} from "./blocks/slices";
import { clientApp } from "./client-app";

/**
 * The config slices of the block instances whose hooks the browser runs
 * (`src/hooks`). Records bring the slices of the blocks they bind.
 */
export const bsb = createClient(clientApp, {
  env: {
    url: env.NEXT_PUBLIC_SUPABASE_URL,
    publishableKey: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  },
  blocks: {
    announcements: announcementsConfig,
    "api-keys": apiKeysConfig,
    attachments: attachmentsConfig,
    audit: auditConfig,
    automations: automationsConfig,
    comments: commentsConfig,
    entitlements: entitlementsConfig,
    inbox: inboxConfig,
    messaging: messagingConfig,
    notifications: notificationsConfig,
    onboarding: onboardingConfig,
    organizations: organizationsConfig,
    permissions: permissionsConfig,
    reactions: reactionsConfig,
    search: searchConfig,
    sessions: sessionsConfig,
    settings: settingsConfig,
    subjects: subjectsConfig,
    tags: tagsConfig,
    usage: usageConfig,
    "workflow-editor": workflowEditorConfig,
    workflows: workflowsConfig,
  },
});
