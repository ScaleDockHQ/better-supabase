import { sessionStatusRoute } from "better-supabase/server";

import { bsb } from "../../../lib/supabase/server";

/** What `useSessionWatch()` polls: whether the session still holds. */
export const GET = sessionStatusRoute(bsb);
