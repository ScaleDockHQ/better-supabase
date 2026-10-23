import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: { source: { snapshot: "../../../supabase/snapshot.json" } },
  gen: {
    casing: "snake",
    output: "src/lib/supabase/generated.ts",
    hooks: "react",
  },
});
