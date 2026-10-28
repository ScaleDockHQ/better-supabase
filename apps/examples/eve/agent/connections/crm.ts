import { openApiAuth, tenantArgument } from "better-supabase/eve";
import { defineOpenAPIConnection } from "eve/connections";

import { credentials } from "../lib/blocks";

// One CRM API key for the app, stored in Vault (`credentials.set` with the app
// subject). Every operation gets the session's organization as
// `organization_id`, so the model can neither see nor change it.
export default defineOpenAPIConnection({
  spec: "https://crm.example.com/openapi.json",
  description: "The organization's CRM: accounts, contacts and open deals",
  auth: openApiAuth({
    provider: credentials,
    ref: { provider: "vault", secret: "crm", scope: "app" },
    owner: "app",
    connection: "CRM",
  }),
  toolCall: { providedArguments: tenantArgument("organization_id") },
});
