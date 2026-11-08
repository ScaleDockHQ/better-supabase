import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: {
    source: { snapshot: "../../../supabase/snapshot.json" },
    expose: { notes: ["select", "insert"] },
  },
  gen: { casing: "camel", file: "lib/supabase/generated.ts" },
});
