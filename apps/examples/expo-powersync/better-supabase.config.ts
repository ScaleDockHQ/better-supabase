import { defineConfig } from "better-supabase/config";

export default defineConfig({
  source: { snapshot: "../../../supabase/snapshot.json" },
  casing: "snake",
  output: "src/lib/supabase/generated.ts",
});
