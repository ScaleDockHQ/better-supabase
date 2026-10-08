import { credentialAuth } from "better-supabase/eve";
import { defineMcpClientConnection } from "eve/connections";

import { credentials } from "../lib/blocks";

// Each member stores their own Linear token in Vault (`credentials.set` with
// their user subject); until they do, eve reports `authorization.required`.
export default defineMcpClientConnection({
  url: "https://mcp.linear.app/mcp",
  description: "The member's Linear workspace: issues, projects and cycles",
  auth: credentialAuth({
    provider: credentials,
    ref: { provider: "vault", secret: "linear", scope: "user" },
    owner: "user",
    connection: "Linear",
  }),
});
