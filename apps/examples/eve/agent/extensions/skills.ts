import {
  supabaseDocumentBackend,
  supabaseSkillScopes,
} from "better-supabase/eve";
import customSkills from "eve/experimental/extensions/custom-skills";

import { memory } from "../lib/blocks";

export default customSkills({
  storage: supabaseDocumentBackend({ memory, scope: "skills" }),
  scopes: supabaseSkillScopes({ organization: { writableBy: ["owner"] } }),
});
