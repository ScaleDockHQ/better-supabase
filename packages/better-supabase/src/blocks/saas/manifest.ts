import type { BlockOf } from "../define-block.ts";

import { apiKeysBlock } from "../api-keys/manifest.ts";
import { auditBlock } from "../audit/manifest.ts";
import { billingBlock } from "../billing/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { entitlementsBlock } from "../entitlements/manifest.ts";
import { notificationsBlock } from "../notifications/manifest.ts";
import { onboardingBlock } from "../onboarding/manifest.ts";
import { organizationsBlock } from "../organizations/manifest.ts";
import { outboxBlock } from "../outbox/manifest.ts";
import { profilesBlock } from "../profiles/manifest.ts";
import { settingsBlock } from "../settings/manifest.ts";
import { teamsBlock } from "../teams/manifest.ts";
import { createSaas } from "./saas.ts";

/** The blocks `saas` is made of, by block name. */
export const saasParts: {
  readonly organizations: typeof organizationsBlock;
  readonly teams: typeof teamsBlock;
  readonly profiles: typeof profilesBlock;
  readonly billing: typeof billingBlock;
  readonly entitlements: typeof entitlementsBlock;
  readonly notifications: typeof notificationsBlock;
  readonly audit: typeof auditBlock;
  readonly "api-keys": typeof apiKeysBlock;
  readonly settings: typeof settingsBlock;
  readonly onboarding: typeof onboardingBlock;
  readonly outbox: typeof outboxBlock;
} = {
  organizations: organizationsBlock,
  teams: teamsBlock,
  profiles: profilesBlock,
  billing: billingBlock,
  entitlements: entitlementsBlock,
  notifications: notificationsBlock,
  audit: auditBlock,
  "api-keys": apiKeysBlock,
  settings: settingsBlock,
  onboarding: onboardingBlock,
  outbox: outboxBlock,
};

export type SaasParts = typeof saasParts;

/**
 * The `saas` composite (ADR 0177): organizations with invitations and teams,
 * billing and entitlements, notifications, the audit log, API keys, settings
 * and onboarding. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const saasBlock: BlockOf<"saas", typeof createSaas> = defineBlock({
  name: "saas",
  composes: saasParts,
  create: createSaas,
  category: "tenancy",
});
