import { defineFramework } from "better-supabase/plugins";

/** A framework binding that lives outside the library. */
export const qwik = defineFramework({
  name: "qwik",
  tier: "community",
  detect: ["@builder.io/qwik"],
  hooksModule: "@acme/qwik-hooks",
  hooksDirective: '"use qwik";',
});
