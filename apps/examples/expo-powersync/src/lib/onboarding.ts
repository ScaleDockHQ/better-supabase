import { defineChecklist } from "better-supabase/blocks/onboarding";

/**
 * The organization's getting-started checklist, the same steps as the one the
 * Next.js example passes to the onboarding SQL module.
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
