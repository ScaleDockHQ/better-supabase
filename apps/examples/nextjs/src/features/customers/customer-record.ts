import "server-only";
import { customerRecord } from "@/lib/supabase/records/customer";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The customer page: `load` and `timeline` for Server Components, and one
 * Server Action per binding write in `actions`.
 */
export const customerPage = bsbCore.record(customerRecord);
