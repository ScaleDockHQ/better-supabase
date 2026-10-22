import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: { source: { snapshot: "../../../../supabase/snapshot.json" } },
  gen: { casing: "camel", output: "src/generated.ts" },
});
