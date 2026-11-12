"use client";

import { useExtracted } from "next-intl";

import type { SettingsTabId } from "../settings-tabs";

export function useTabLabel(): (id: SettingsTabId) => string {
  const t = useExtracted("settings");

  return (id: SettingsTabId): string => {
    switch (id) {
      case "profile": {
        return t("Profile");
      }

      case "preferences": {
        return t("Preferences");
      }

      case "integrations": {
        return t("Integrations");
      }

      case "security": {
        return t("Security");
      }

      case "privacy": {
        return t("Privacy");
      }

      case "organization": {
        return t("Organization");
      }

      case "members": {
        return t("Members");
      }

      case "teams": {
        return t("Teams");
      }

      case "roles": {
        return t("Roles");
      }

      case "accessRequests": {
        return t("Access requests");
      }

      case "billing": {
        return t("Billing");
      }

      case "apiKeys": {
        return t("API keys");
      }

      case "webhooks": {
        return t("Webhooks");
      }

      case "incomingWebhooks": {
        return t("Incoming webhooks");
      }

      case "domains": {
        return t("Domains");
      }

      case "optionSets": {
        return t("Option sets");
      }

      case "flags": {
        return t("Flags");
      }

      case "numbering": {
        return t("Numbering");
      }

      case "securityEvents": {
        return t("Security events");
      }

      case "oauthApps": {
        return t("OAuth apps");
      }

      case "searchSettings": {
        return t("Search index");
      }

      case "signingKeys": {
        return t("Signing keys");
      }

      case "support": {
        return t("Support sessions");
      }

      case "marketplace": {
        return t("Vercel Marketplace");
      }

      case "billingAccount": {
        return t("Billing account");
      }

      case "sso": {
        return t("Single sign-on");
      }

      case "customFields": {
        return t("Custom fields");
      }

      case "jobs": {
        return t("Jobs");
      }

      case "audit": {
        return t("Audit log");
      }

      case "aiProviders": {
        return t("AI providers");
      }

      default: {
        const unknown: never = id;

        return unknown;
      }
    }
  };
}
