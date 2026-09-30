import { defineConfig } from "better-supabase/config";

export default defineConfig({
  source: { snapshot: "../../../supabase/snapshot.json" },
  casing: "camel",
  output: "lib/supabase/generated.ts",
});
