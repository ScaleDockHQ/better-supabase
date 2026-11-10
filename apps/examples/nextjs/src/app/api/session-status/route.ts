import { sessionStatusRoute } from "better-supabase/server/accounts";

import { bsbCore as bsb } from "../../../lib/supabase/server-core";

/** What `useSessionWatch()` polls: whether the session still holds. */
export const GET = sessionStatusRoute(bsb);
