import { supabaseJwtAuth } from "better-supabase/eve";
import { oauthResource } from "eve/channels/auth";
import { mcpChannel } from "eve/channels/mcp";

import { env } from "../lib/blocks";

// MCP clients send a member's access token as a bearer token; the session
// cookie never counts here, so another site can't call the tools through a
// signed-in browser.
export default mcpChannel({
  auth: oauthResource(supabaseJwtAuth({ env }), {
    issuer: `${env.url}/auth/v1`,
  }),
});
