import { createEnv } from "@t3-oss/env-nextjs";
import * as v from "valibot";

export const env = createEnv({
  shared: {
    NODE_ENV: v.optional(
      v.picklist(["development", "test", "production"]),
      "development",
    ),
  },
  server: {
    // In development the docs app runs on its own port; in production Vercel
    // Services routes /docs to it and this is unused.
    DOCS_ORIGIN: v.optional(
      v.pipe(v.string(), v.url()),
      "http://127.0.0.1:3001",
    ),
  },
  client: {},
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    DOCS_ORIGIN: process.env["DOCS_ORIGIN"],
  },
  emptyStringAsUndefined: true,
});
