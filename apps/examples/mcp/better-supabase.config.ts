import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: { source: { snapshot: "../../../supabase/snapshot.json" } },
  gen: { casing: "camel", file: "lib/supabase/generated.ts" },
});
