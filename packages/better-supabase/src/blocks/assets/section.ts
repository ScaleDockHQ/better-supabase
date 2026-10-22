import type { Section } from "../sections.ts";
import type { Asset, Assets } from "./assets.ts";

import { defineSection } from "../sections.ts";

/** The assets a record holds, such as a party's devices or vehicles. */
export const assetsSection: Section<Assets, readonly Asset[]> = defineSection({
  permissions: { read: "read", write: "assign" },
  module: "assets",
  load: (client: Assets, subject) => client.assignedTo(subject),
  events: ["asset.*"],
});
