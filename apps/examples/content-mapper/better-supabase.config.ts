import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: { source: { snapshot: "../../../supabase/snapshot.json" } },
  gen: {
    casing: "camel",
    output: "src/lib/supabase/generated.ts",
    contentMapper: true,
  },
});
