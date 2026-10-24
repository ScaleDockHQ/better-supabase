import { createClient } from "@supabase/supabase-js";

import type { Database } from "./lib/supabase/index.ts";

import { betterSupabase } from "./lib/supabase/index.ts";

const supabase = createClient<Database>(
  process.env["SUPABASE_URL"] ?? "http://127.0.0.1:54321",
  process.env["SUPABASE_PUBLISHABLE_KEY"] ?? "",
);

const db = betterSupabase.connect(supabase);

const customers = await db.customers
  .list({
    select: ["id", "name", "status"],
    orderBy: { name: "asc" },
    limit: 10,
  })
  .orThrow();

for (const customer of customers) {
  console.log(`${customer.name} (${customer.status})`);
}
