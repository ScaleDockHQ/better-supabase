import type { ToolSet } from "ai";

import "server-only";
import { tool } from "ai";
import * as v from "valibot";

import type {
  Permission,
  PermissionSet,
} from "@/features/user/user-permissions";

import { agentsBlock } from "@/features/agents/agents-server";
import { APPROVAL_SUBJECT } from "@/features/approvals/approvals-types";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import type { PageContext, PageRecordType } from "./page-context";

/** The permission that lets the caller read each record type. */
const READ_PERMISSION: Readonly<Record<PageRecordType, Permission>> = {
  deal: "deals.read",
  contract: "contracts.read",
  quote: "quotes.read",
  customer: "customers.read",
  agent: "agents.read",
};

/** The record types the caller may read, whatever the page shows. */
export function readableRecordTypes(
  permissions: PermissionSet | null,
): readonly PageRecordType[] {
  // SAFETY: READ_PERMISSION is keyed by every PageRecordType, so its keys are exactly that union.
  return (Object.keys(READ_PERMISSION) as PageRecordType[]).filter((type) =>
    can(permissions, READ_PERMISSION[type]),
  );
}

type Summary = Readonly<Record<string, string | number | boolean | null>>;

/**
 * One record as the caller may read it, as plain JSON. Every read goes through
 * the caller's own session, so row policies apply a second time.
 */
async function summarize(
  type: PageRecordType,
  id: string,
): Promise<Summary | null> {
  const { db, supabase } = await bsb.context();

  switch (type) {
    case "deal": {
      const found = await db.deals.get(id);

      return found.ok
        ? {
            identifier: found.data.identifier,
            name: found.data.name,
            outcome: found.data.outcome,
            amount: found.data.amount.amount.toString(),
            currency: found.data.currency,
            closeOn: found.data.closeOn.toString(),
          }
        : null;
    }

    case "contract": {
      const found = await db.contracts.get(id);

      return found.ok
        ? {
            title: found.data.title,
            status: found.data.status,
            autoRenew: found.data.autoRenew,
            endsOn: found.data.endsOn?.toString() ?? null,
          }
        : null;
    }

    case "quote": {
      const found = await db.quotes.get(id);

      return found.ok
        ? {
            identifier: found.data.identifier,
            title: found.data.title,
            status: found.data.status,
            currency: found.data.currency,
          }
        : null;
    }

    case "customer": {
      const found = await db.customers.get(id, {
        select: ["id", "name", "status"],
      });

      return found.ok
        ? { name: found.data.name, status: found.data.status }
        : null;
    }

    case "agent": {
      const found = await agentsBlock(supabase).get(id);

      return found.ok
        ? {
            name: found.data.name,
            slug: found.data.slug,
            visibility: found.data.visibility,
            tools: found.data.tools.length,
          }
        : null;
    }

    default: {
      const unreachable: never = type;

      return unreachable;
    }
  }
}

const NoInput = v.object({});

const DiscountRequest = v.object({
  customerId: v.pipe(v.string(), v.uuid()),
  reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
});

/**
 * The tools that know about the page the assistant was opened on. Reads cover
 * only what the caller's permissions allow. The one write files an approval
 * request under the customer policy; it changes nothing until an approver
 * decides it on the approvals page, so the assistant never writes directly.
 */
export function pageTools(
  page: PageContext | undefined,
  permissions: PermissionSet | null,
): ToolSet {
  const readable = readableRecordTypes(permissions);

  const tools: ToolSet = {
    readCurrentPage: tool({
      description:
        "Reads the page the user opened the assistant from: its path and, on a record page, the record's key fields. Returns what the user may read and nothing else.",
      inputSchema: NoInput,
      execute: async () => {
        if (page === undefined) {
          return { path: null, record: null, readable };
        }

        const { recordType, recordId } = page;

        if (recordType === undefined || recordId === undefined) {
          return { path: page.path, record: null, readable };
        }

        if (!readable.includes(recordType)) {
          return {
            path: page.path,
            record: null,
            denied: `Your role cannot read ${recordType} records`,
            readable,
          };
        }

        return {
          path: page.path,
          recordType,
          record: await summarize(recordType, recordId),
          readable,
        };
      },
    }),
  };

  if (can(permissions, "approvals.request")) {
    tools["requestDiscountApproval"] = tool({
      description:
        "Files an approval request for a customer discount. It changes nothing until an approver decides it. Use it when the user asks for a discount, with the reason in the user's words.",
      inputSchema: DiscountRequest,
      execute: async ({ customerId, reason }) => {
        const { db } = await bsb.context();

        const requested = await db.approvals.request({
          subject: { type: APPROVAL_SUBJECT, id: customerId },
          input: { action: "discount", reason },
        });

        return requested.ok
          ? { requested: true, approvalId: requested.data.id }
          : { requested: false, error: requested.error.message };
      },
    });
  }

  return tools;
}
