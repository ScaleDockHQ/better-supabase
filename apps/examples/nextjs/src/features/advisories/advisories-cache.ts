import { tagFor } from "better-supabase/next";

/**
 * Every read of the products, vulnerabilities and advisories carries this tag,
 * and every write of its actions expires it through `refreshCaller(auth,
 * [ADVISORIES_TAG])`.
 */
export const ADVISORIES_TAG = tagFor("advisories");
