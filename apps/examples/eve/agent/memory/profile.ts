import { supabaseMemory } from "better-supabase/eve";
import { defineMemory, defineMemoryProvider } from "eve/memory";
import { byPrincipal } from "eve/memory/scope";

import { knowledge, memory } from "../lib/blocks";

export default defineMemory({
  description: "What the assistant knows about this member and their team",
  scope: byPrincipal,
  // The member's own memory, plus what the team shares (read-only here).
  provider: defineMemoryProvider(
    supabaseMemory({ memory, knowledge, scopes: ["user", "organization"] }),
  ),
});
