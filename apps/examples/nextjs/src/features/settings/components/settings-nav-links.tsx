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

      case "signingKeys": {
        return t("Signing keys");
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
