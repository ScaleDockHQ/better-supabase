import { createOutbox, sqlTransport } from "better-supabase/blocks/outbox";

import { postgres } from "@/lib/postgres";

/**
 * The outbox on the server connection. Register each consumer once, for example
 * in a migration script or at the top of the relay route: `await
 * outbox.register("search", { types: ["customer.*"] })`.
 */
export const outbox = createOutbox({
  transport: sqlTransport(postgres.admin),
  source: process.env.APP_URL ?? "http://localhost:3000",
  typePrefix: "com.example.app",
});
