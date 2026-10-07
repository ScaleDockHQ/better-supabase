import { defineChecklist } from "better-supabase/blocks/onboarding";

/**
 * The organization's getting-started checklist. better-supabase.config.ts
 * passes it to the onboarding SQL module, so the database knows the steps;
 * the actions that add a customer, invite a teammate and create an API key
 * complete them.
 */
export const gettingStarted = defineChecklist({
  id: "getting-started",
  scope: "organization",
  steps: [
    { id: "customer", title: "Add your first customer", href: "/customers" },
    { id: "invite", title: "Invite a teammate", href: "/settings/members" },
    { id: "api-key", title: "Create an API key", href: "/settings/api-keys" },
    { id: "plan", title: "Review your plan", href: "/settings/billing" },
  ],
});
