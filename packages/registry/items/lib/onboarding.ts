import { defineChecklist } from "better-supabase/blocks/onboarding";

/**
 * The organization's getting-started checklist. Pass it to the onboarding
 * block in `better-supabase.config.ts` too, so the database knows the steps:
 * `blocks: { onboarding: { options: { checklists: [gettingStarted] } } }`.
 * Complete a step from the action that does it, with
 * `blocks(supabase).onboarding.complete(gettingStarted, "invite", organizationId)`.
 */
export const gettingStarted = defineChecklist({
  id: "getting-started",
  scope: "organization",
  steps: [
    { id: "invite", title: "Invite a teammate", href: "/settings/members" },
    { id: "api-key", title: "Create an API key", href: "/settings/api-keys" },
    { id: "plan", title: "Pick a plan", href: "/settings/billing" },
  ],
});
