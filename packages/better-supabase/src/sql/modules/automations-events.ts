import type { AutomationsEvents } from "../../blocks/automations/events.ts";
import type { BlockSqlEvents } from "../context.ts";

const RULE_PAYLOAD = [
  "organizationId",
  "ruleId",
  "name",
  "subjectType",
  "trigger",
  "version",
] as const;

export const EVENTS: BlockSqlEvents<AutomationsEvents> = {
  "rule.saved": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.enabled": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.disabled": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.removed": { subject: "rules", payload: RULE_PAYLOAD },
  "rule.matched": {
    subject: "rules",
    payload: [
      "organizationId",
      "ruleId",
      "version",
      "subjectType",
      "subjectId",
      "trigger",
    ],
  },
};
