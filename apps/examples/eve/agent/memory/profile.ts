import { supabaseMemory } from "better-supabase/eve";
import { defineMemory, defineMemoryProvider } from "eve/memory";
import { byPrincipal } from "eve/memory/scope";

import { knowledge, memory } from "../lib/blocks";

export default defineMemory({
  description: "What the assistant knows about this member and their team",
  scope: byPrincipal,
  provider: defineMemoryProvider(supabaseMemory({ memory, knowledge })),
});
