import "server-only";
import { customerRecord } from "@/lib/supabase/records/customer";
import { bsb } from "@/lib/supabase/server";

/**
 * The customer page: `load` and `timeline` for Server Components, and one
 * Server Action per binding write in `actions`.
 */
export const customerPage = bsb.record(customerRecord);
