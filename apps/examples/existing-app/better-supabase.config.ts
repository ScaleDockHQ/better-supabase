import { defineConfig } from "better-supabase/config";

// Rung 1: `better-supabase init` writes this from the supabase folder.
// Rung 4 adds blocks: `better-supabase add comments --over public.notes`.
export default defineConfig({
  gen: { casing: "camel", output: "src/lib/supabase/generated.ts" },
});
