import { supabaseDocumentBackend } from "better-supabase/eve";
import { defineMemory } from "eve/memory";
import { fileMemory } from "eve/memory/file";
import { byPrincipal } from "eve/memory/scope";

import { memory } from "../lib/blocks";

export default defineMemory({
  description: "Short notes the assistant keeps for itself about this member",
  scope: byPrincipal,
  provider: fileMemory({ backend: supabaseDocumentBackend({ memory }) }),
});
