"use client";

import { useExtracted } from "next-intl";

/** `snake_case` as a sentence: `custom_thing` is "Custom thing". */
function humanize(type: string): string {
  const words = type.replaceAll("_", " ");

  return `${words.slice(0, 1).toUpperCase()}${words.slice(1)}`;
}

/**
 * The plural heading of a subject type in search results. A type this app does
 * not name falls back to its key, so a block added later still shows.
 */
export function useSubjectTypeLabel(): (type: string) => string {
  const t = useExtracted("search");

  return (type: string): string => {
    switch (type) {
      case "message": {
        return t("Messages");
      }

      case "conversation": {
        return t("Conversations");
      }

      case "channel": {
        return t("Channels");
      }

      case "company": {
        return t("Companies");
      }

      case "person": {
        return t("People");
      }

      case "deal": {
        return t("Deals");
      }

      case "course": {
        return t("Courses");
      }

      case "post": {
        return t("Posts");
      }

      case "activity": {
        return t("Activities");
      }

      case "quote": {
        return t("Quotes");
      }

      case "work_item": {
        return t("Work items");
      }

      case "employee": {
        return t("Employees");
      }

      case "invoice": {
        return t("Invoices");
      }

      case "ledger_account": {
        return t("Ledger accounts");
      }

      case "product": {
        return t("Products");
      }

      case "product_variant": {
        return t("Product variants");
      }

      case "rfq": {
        return t("Requests for quotation");
      }

      case "till": {
        return t("Tills");
      }

      case "order": {
        return t("Orders");
      }

      case "calendar_event": {
        return t("Calendar events");
      }

      case "booking": {
        return t("Bookings");
      }

      case "asset": {
        return t("Assets");
      }

      case "lease": {
        return t("Leases");
      }

      case "expense_report": {
        return t("Expense reports");
      }

      case "shipment": {
        return t("Shipments");
      }

      case "contract": {
        return t("Contracts");
      }

      case "risk": {
        return t("Risks");
      }

      case "case": {
        return t("Cases");
      }

      case "inspection": {
        return t("Inspections");
      }

      case "form": {
        return t("Forms");
      }

      case "meeting": {
        return t("Meetings");
      }

      case "maintenance_plan": {
        return t("Maintenance plans");
      }

      case "lims_sample": {
        return t("Laboratory samples");
      }

      case "production_order": {
        return t("Production orders");
      }

      case "care_plan": {
        return t("Care plans");
      }

      case "incident": {
        return t("Incidents");
      }

      case "content_entry": {
        return t("Content");
      }

      case "document": {
        return t("Documents");
      }

      case "customer": {
        return t("Customers");
      }

      case "drive_node": {
        return t("Files and folders");
      }

      case "project": {
        return t("Projects");
      }

      case "task": {
        return t("Tasks");
      }

      case "work_order": {
        return t("Work orders");
      }

      default: {
        return humanize(type);
      }
    }
  };
}

/** A subject type's heading, for a server component's list. */
export function SubjectTypeLabel({ type }: { type: string }) {
  return useSubjectTypeLabel()(type);
}
