"use client";

import { useExtracted } from "next-intl";

import type { NavId } from "../nav-items";

export function useNavLabel(): (id: NavId) => string {
  const t = useExtracted("navigation");

  return (id: NavId): string => {
    switch (id) {
      case "dashboard": {
        return t("Dashboard");
      }

      case "myWork": {
        return t("My work");
      }

      case "customers": {
        return t("Customers");
      }

      case "work": {
        return t("Work");
      }

      case "workGrid": {
        return t("Work grid");
      }

      case "projects": {
        return t("Projects");
      }

      case "approvals": {
        return t("Approvals");
      }

      case "rules": {
        return t("Rules");
      }

      case "people": {
        return t("People");
      }

      case "hiring": {
        return t("Hiring");
      }

      case "leave": {
        return t("Leave");
      }

      case "onboarding": {
        return t("Onboarding");
      }

      case "deadlines": {
        return t("Deadlines");
      }

      case "documentRegister": {
        return t("Document register");
      }

      case "documentTemplates": {
        return t("Document templates");
      }

      case "time": {
        return t("Time");
      }

      case "calendar": {
        return t("Calendar");
      }

      case "availability": {
        return t("Availability");
      }

      case "frontDesk": {
        return t("Front desk");
      }

      case "contacts": {
        return t("Contacts");
      }

      case "deals": {
        return t("Deals");
      }

      case "sequences": {
        return t("Sequences");
      }

      case "quotes": {
        return t("Quotes");
      }

      case "salesHome": {
        return t("Sales overview");
      }

      case "pipelines": {
        return t("Pipelines");
      }

      case "forecasts": {
        return t("Forecasts");
      }

      case "segments": {
        return t("Segments");
      }

      case "queues": {
        return t("Queues");
      }

      case "scoring": {
        return t("Scoring");
      }

      case "contracts": {
        return t("Contracts");
      }

      case "commissions": {
        return t("Commissions");
      }

      case "referrals": {
        return t("Referrals");
      }

      case "customerSuccess": {
        return t("Customer success");
      }

      case "shop": {
        return t("Shop");
      }

      case "inventory": {
        return t("Inventory");
      }

      case "manufacturing": {
        return t("Manufacturing");
      }

      case "production": {
        return t("Production planning");
      }

      case "banking": {
        return t("Banking");
      }

      case "legalEntities": {
        return t("Legal entities");
      }

      case "payrollExport": {
        return t("Payroll export");
      }

      case "orders": {
        return t("Orders");
      }

      case "dispatch": {
        return t("Dispatch");
      }

      case "myDay": {
        return t("My day");
      }

      case "shipments": {
        return t("Shipments");
      }

      case "drive": {
        return t("Drive");
      }

      case "documents": {
        return t("Documents");
      }

      case "forms": {
        return t("Forms");
      }

      case "courses": {
        return t("Courses");
      }

      case "community": {
        return t("Community");
      }

      case "templates": {
        return t("Templates");
      }

      case "imports": {
        return t("Imports");
      }

      case "trash": {
        return t("Trash");
      }

      case "metrics": {
        return t("Metrics");
      }

      case "compliance": {
        return t("Compliance");
      }

      case "qualifications": {
        return t("Qualifications");
      }

      case "risks": {
        return t("Risks");
      }

      case "cases": {
        return t("Cases");
      }

      case "announcements": {
        return t("Announcements");
      }

      case "advisories": {
        return t("Advisories");
      }

      case "content": {
        return t("Content");
      }

      case "moderation": {
        return t("Moderation");
      }

      case "incidents": {
        return t("Incidents");
      }

      case "inspections": {
        return t("Audits and inspections");
      }

      case "meetings": {
        return t("Meetings");
      }

      case "dam": {
        return t("Assets");
      }

      case "lims": {
        return t("Laboratory");
      }

      case "rfqs": {
        return t("Requests for quotation");
      }

      case "donations": {
        return t("Donations");
      }

      case "warranty": {
        return t("Warranty");
      }

      case "reviews": {
        return t("Reviews");
      }

      case "collections": {
        return t("Collections");
      }

      case "checkoutSessions": {
        return t("Checkout sessions");
      }

      case "passes": {
        return t("Passes");
      }

      case "leases": {
        return t("Leases");
      }

      case "assets": {
        return t("Asset register");
      }

      case "tills": {
        return t("Tills");
      }

      case "maintenance": {
        return t("Maintenance");
      }

      case "appraisals": {
        return t("Appraisals");
      }

      case "warehouse": {
        return t("Warehouse");
      }

      case "shifts": {
        return t("Shifts");
      }

      case "finance": {
        return t("Finance");
      }

      case "payables": {
        return t("Payables");
      }

      case "invoices": {
        return t("Invoices");
      }

      case "expenses": {
        return t("Expenses");
      }

      case "ledger": {
        return t("Ledger");
      }

      case "accountingBooks": {
        return t("Books");
      }

      case "billableTime": {
        return t("Billable time");
      }

      case "recurring": {
        return t("Recurring charges");
      }

      case "tax": {
        return t("Tax");
      }

      case "periods": {
        return t("Periods");
      }

      case "care": {
        return t("Clients");
      }

      case "observations": {
        return t("Observations");
      }

      case "medications": {
        return t("Medications");
      }

      case "careAlerts": {
        return t("Care alerts");
      }

      case "prescriptions": {
        return t("Prescriptions");
      }

      case "carePlans": {
        return t("Care plans");
      }

      case "funding": {
        return t("Funding");
      }

      case "notifications": {
        return t("Notifications");
      }

      case "workflows": {
        return t("Workflows");
      }

      case "workflowRuns": {
        return t("Workflow runs");
      }

      case "inbox": {
        return t("Inbox");
      }

      case "chat": {
        return t("Chat");
      }

      case "assistant": {
        return t("Assistant");
      }

      case "knowledge": {
        return t("Knowledge");
      }

      case "agentActivity": {
        return t("Agent activity");
      }

      case "agents": {
        return t("Agents");
      }

      case "prompts": {
        return t("Prompts");
      }

      case "evals": {
        return t("Evals");
      }

      case "guardrails": {
        return t("Guardrails");
      }

      case "aiUsage": {
        return t("AI usage");
      }

      case "aiTasks": {
        return t("AI tasks");
      }

      case "beta": {
        return t("Beta");
      }

      case "islands": {
        return t("Islands");
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

      case "billing": {
        return t("Billing");
      }

      case "apiKeys": {
        return t("API keys");
      }

      case "audit": {
        return t("Audit log");
      }

      case "aiProviders": {
        return t("AI providers");
      }

      case "settings": {
        return t("Settings");
      }

      default: {
        const unknown: never = id;

        return unknown;
      }
    }
  };
}
