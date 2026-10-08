import { supabaseAuth } from "better-supabase/eve";
import { localDev } from "eve/channels/auth";
import { eveChannel } from "eve/channels/eve";

import { env } from "../lib/blocks";

// A signed-in member's bearer token or cookie first; `localDev` lets the eve
// dev tools in without one, and only on localhost.
export default eveChannel({
  auth: [supabaseAuth({ env }), localDev()],
});
