import type { Section } from "../sections.ts";
import type { Score, Scores } from "./scores.ts";

import { defineSection } from "../sections.ts";

/** A record's current scores, such as a lead score or account health. */
export const scoresSection: Section<Scores, readonly Score[]> = defineSection({
  permissions: { read: "read", write: "compute" },
  module: "scores",
  load: (client: Scores, subject) => client.list({ on: subject }),
  events: ["score.changed"],
});
