import "server-only";
import { projectRecord } from "@/lib/supabase/records/project";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The project page: `load` and `timeline` for Server Components, and one Server
 * Action per binding write in `actions`.
 */
export const projectPage = bsbCore.record(projectRecord);
