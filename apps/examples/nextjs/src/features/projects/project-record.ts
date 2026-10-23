import "server-only";
import { projectRecord } from "@/lib/supabase/records/project";
import { bsb } from "@/lib/supabase/server";

/**
 * The project page: `load` and `timeline` for Server Components, and one Server
 * Action per binding write in `actions`.
 */
export const projectPage = bsb.record(projectRecord);
