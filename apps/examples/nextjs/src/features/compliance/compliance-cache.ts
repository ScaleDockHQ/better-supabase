import { tagFor } from "better-supabase/next";

/** Every read of compliance carries this tag; adding evidence expires it. */
export const COMPLIANCE_TAG = tagFor("compliance");
