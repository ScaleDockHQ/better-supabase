import {
  BadgePercentIcon,
  GiftIcon,
  ReceiptIcon,
  Share2Icon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";

import { loadMemberOptions } from "../member/member-queries";
import { loadCommissions, loadReferrals } from "../revenue/revenue-queries";
import {
  buildCommissionStatement,
  createCommissionPlan,
  createReferralCode,
} from "../sales-actions";
import { ActionDialog } from "./action-dialog";
import { BlockOverview } from "./block-overview";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

export type CommissionTab = "plans" | "commissions" | "statements";

export type ReferralTab = "codes" | "referrals";

async function namesOf(): Promise<(userId: string) => string> {
  const members = await loadMemberOptions();
  const names = new Map(members.map((member) => [member.userId, member.name]));

  return (userId) => names.get(userId) ?? userId;
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreatePlanDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createCommissionPlan}
      title={t("New commission plan")}
      description={t("A flat plan pays a share of every sale a seller closes.")}
      trigger={t("New plan")}
      submitLabel={t("Create plan")}
      successMessage={t("Plan created")}
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "rate",
          label: t("Rate in percent"),
          kind: "decimal",
          required: true,
          placeholder: "5",
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function BuildStatementDialog() {
  const t = await getExtracted("sales");
  const members = await loadMemberOptions();
  const today = new Date();

  const since = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1),
  );

  const until = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0),
  );

  if (members.length === 0) {
    return null;
  }

  return (
    <ActionDialog
      action={buildCommissionStatement}
      title={t("Build a statement")}
      description={t(
        "Collects the seller's accrued commissions of the period.",
      )}
      trigger={t("Build statement")}
      submitLabel={t("Build statement")}
      successMessage={t("Statement built")}
      redirectTo="/crm/commissions/statements/{id}"
      variant="outline"
      fields={[
        {
          name: "sellerId",
          label: t("Seller"),
          kind: "select",
          options: members.map((member) => ({
            value: member.userId,
            label: member.name,
          })),
        },
        {
          name: "currency",
          label: t("Currency"),
          kind: "select",
          options: [
            { value: "EUR", label: "EUR" },
            { value: "USD", label: "USD" },
            { value: "GBP", label: "GBP" },
          ],
        },
        {
          name: "startsOn",
          label: t("From"),
          kind: "date",
          required: true,
          defaultValue: since.toISOString().slice(0, 10),
        },
        {
          name: "endsOn",
          label: t("Until"),
          kind: "date",
          required: true,
          defaultValue: until.toISOString().slice(0, 10),
        },
      ]}
    />
  );
}

/** One of the three commission lists, chosen by the page's `tab`. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CommissionOverview({
  query,
  tab,
}: {
  query: BlockListQuery;
  tab: CommissionTab;
}) {
  await requirePermission("commissions.read");

  const [t, loaded, fmtMoney, fmtDate, nameOf, canManage] = await Promise.all([
    getExtracted("sales"),
    settle(loadCommissions),
    moneyFormatter(),
    dateFormatter(),
    namesOf(),
    holds("commissions.manage"),
  ]);

  const common = {
    query,
    errorTitle: t("The commissions didn't load"),
  } as const;

  const accrued = { accrued: t("Accrued"), reversed: t("Reversed") };

  const statementStates = {
    open: t("Open"),
    finalized: t("Finalized"),
    paid: t("Paid"),
  };

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={common.errorTitle} />;
  }

  if (tab === "plans") {
    return (
      <BlockOverview
        {...common}
        loaded={{ kind: "ok", data: loaded.data.plans }}
        spec={{
          search: (plan) => plan.name,
          facet: (plan) => plan.kind,
          defaultSort: "name",
          sorts: { name: (a, b) => a.name.localeCompare(b.name) },
        }}
        toRow={(plan) => ({
          id: plan.id,
          name: plan.name,
          kind: plan.kind,
          rate: plan.rateBps === null ? null : `${plan.rateBps / 100}%`,
          tiers: plan.tiers,
          state: plan.archived ? "archived" : "active",
        })}
        columns={[
          { key: "name", header: t("Plan"), kind: "text", size: 260 },
          {
            key: "kind",
            header: t("Kind"),
            kind: "badge",
            size: 110,
            labels: { flat: t("Flat"), tiered: t("Tiered") },
          },
          { key: "rate", header: t("Rate"), kind: "number", size: 100 },
          { key: "tiers", header: t("Tiers"), kind: "number", size: 90 },
          {
            key: "state",
            header: t("State"),
            kind: "badge",
            size: 110,
            labels: { active: t("Active"), archived: t("Archived") },
            tones: { active: "success-light" },
          },
        ]}
        facet={{
          key: "kind",
          label: t("Kind"),
          values: { flat: t("Flat"), tiered: t("Tiered") },
        }}
        sorts={[{ value: "name", label: t("Name") }]}
        searchLabel={t("Search plans")}
        emptyIcon={<BadgePercentIcon />}
        emptyTitle={t("No plans found")}
        emptyDescription={t("Create a plan, then assign it to your sellers.")}
        emptyAction={canManage ? <CreatePlanDialog /> : undefined}
      />
    );
  }

  if (tab === "statements") {
    return (
      <BlockOverview
        {...common}
        loaded={{ kind: "ok", data: loaded.data.statements }}
        spec={{
          search: (statement) =>
            `${nameOf(statement.sellerId)} ${statement.startsOn}`,
          facet: (statement) => statement.status,
          defaultSort: "newest",
          sorts: {
            newest: (a, b) => b.endsOn.localeCompare(a.endsOn),
            total: (a, b) => Number(b.total.amount - a.total.amount),
          },
        }}
        toRow={(statement) => ({
          id: statement.id,
          seller: nameOf(statement.sellerId),
          period: `${fmtDate(statement.startsOn)} – ${fmtDate(statement.endsOn)}`,
          total: fmtMoney(statement.total),
          status: statement.status,
        })}
        columns={[
          {
            key: "seller",
            header: t("Seller"),
            kind: "link",
            href: "/crm/commissions/statements/{id}",
            size: 220,
          },
          { key: "period", header: t("Period"), kind: "muted", size: 260 },
          { key: "total", header: t("Total"), kind: "number", size: 130 },
          {
            key: "status",
            header: t("Status"),
            kind: "badge",
            size: 120,
            labels: statementStates,
            tones: {
              paid: "success-light",
              finalized: "info-light",
              open: "warning-light",
            },
          },
        ]}
        facet={{ key: "status", label: t("Status"), values: statementStates }}
        sorts={[
          { value: "newest", label: t("Newest first") },
          { value: "total", label: t("Largest total") },
        ]}
        searchLabel={t("Search statements")}
        emptyIcon={<ReceiptIcon />}
        emptyTitle={t("No statements found")}
        emptyDescription={t(
          "Build a statement from a seller's accrued commissions.",
        )}
        emptyAction={canManage ? <BuildStatementDialog /> : undefined}
      />
    );
  }

  return (
    <BlockOverview
      {...common}
      loaded={{ kind: "ok", data: loaded.data.commissions }}
      spec={{
        search: (commission) =>
          `${nameOf(commission.sellerId)} ${commission.sourceType}`,
        facet: (commission) => commission.status,
        defaultSort: "newest",
        sorts: {
          newest: (a, b) => b.occurredOn.localeCompare(a.occurredOn),
          amount: (a, b) => Number(b.amount.amount - a.amount.amount),
        },
      }}
      toRow={(commission) => ({
        id: commission.id,
        seller: nameOf(commission.sellerId),
        source: commission.sourceType,
        basis: fmtMoney(commission.basis),
        amount: fmtMoney(commission.amount),
        occurredOn: fmtDate(commission.occurredOn),
        status: commission.status,
      })}
      columns={[
        { key: "seller", header: t("Seller"), kind: "text", size: 220 },
        { key: "source", header: t("Source"), kind: "muted", size: 120 },
        { key: "basis", header: t("Sale"), kind: "number", size: 130 },
        { key: "amount", header: t("Commission"), kind: "number", size: 130 },
        { key: "occurredOn", header: t("Date"), kind: "muted", size: 130 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 110,
          labels: accrued,
          tones: { accrued: "success-light", reversed: "destructive-light" },
        },
      ]}
      facet={{ key: "status", label: t("Status"), values: accrued }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "amount", label: t("Largest commission") },
      ]}
      searchLabel={t("Search commissions")}
      emptyIcon={<BadgePercentIcon />}
      emptyTitle={t("No commissions found")}
      emptyDescription={t(
        "Commissions accrue when a seller's deal or invoice is won.",
      )}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreateCodeDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createReferralCode}
      title={t("New referral code")}
      description={t(
        "Share the code; each qualified referral earns the reward.",
      )}
      trigger={t("New code")}
      submitLabel={t("Create code")}
      successMessage={t("Code created")}
      fields={[
        {
          name: "maxUses",
          label: t("Maximum uses (optional)"),
          kind: "number",
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ReferralOverview({
  query,
  tab,
}: {
  query: BlockListQuery;
  tab: ReferralTab;
}) {
  await requirePermission("referrals.read");

  const [t, loaded, fmtDate, nameOf, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(loadReferrals),
    dateFormatter(),
    namesOf(),
    holds("referrals.write"),
  ]);

  const statuses = {
    attributed: t("Attributed"),
    qualified: t("Qualified"),
    rewarded: t("Rewarded"),
    void: t("Void"),
  };

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The referrals didn't load")} />;
  }

  if (tab === "codes") {
    return (
      <BlockOverview
        query={query}
        errorTitle={t("The referrals didn't load")}
        loaded={{ kind: "ok", data: loaded.data.codes }}
        spec={{
          search: (code) => `${code.code} ${nameOf(code.referrerId)}`,
          facet: (code) => (code.active ? "active" : "inactive"),
          defaultSort: "uses",
          sorts: {
            uses: (a, b) => b.uses - a.uses,
            code: (a, b) => a.code.localeCompare(b.code),
          },
        }}
        toRow={(code) => ({
          id: code.id,
          code: code.code,
          referrer: nameOf(code.referrerId),
          uses:
            code.maxUses === null
              ? `${code.uses}`
              : `${code.uses} / ${code.maxUses}`,
          expiresAt: code.expiresAt ? fmtDate(code.expiresAt) : null,
          state: code.active ? "active" : "inactive",
        })}
        columns={[
          { key: "code", header: t("Code"), kind: "text", size: 160 },
          { key: "referrer", header: t("Referrer"), kind: "text", size: 220 },
          { key: "uses", header: t("Uses"), kind: "number", size: 110 },
          { key: "expiresAt", header: t("Expires"), kind: "muted", size: 130 },
          {
            key: "state",
            header: t("State"),
            kind: "badge",
            size: 110,
            labels: { active: t("Active"), inactive: t("Inactive") },
            tones: { active: "success-light" },
          },
        ]}
        facet={{
          key: "state",
          label: t("State"),
          values: { active: t("Active"), inactive: t("Inactive") },
        }}
        sorts={[
          { value: "uses", label: t("Most used") },
          { value: "code", label: t("Code") },
        ]}
        searchLabel={t("Search codes")}
        emptyIcon={<Share2Icon />}
        emptyTitle={t("No referral codes found")}
        emptyDescription={t(
          "Create a code to share with customers and partners.",
        )}
        emptyAction={canWrite ? <CreateCodeDialog /> : undefined}
      />
    );
  }

  return (
    <BlockOverview
      query={query}
      errorTitle={t("The referrals didn't load")}
      loaded={{ kind: "ok", data: loaded.data.referrals }}
      spec={{
        search: (referral) =>
          `${referral.referredEmail ?? ""} ${nameOf(referral.referrerId)}`,
        facet: (referral) => referral.status,
        defaultSort: "newest",
        sorts: { newest: (a, b) => b.createdAt.localeCompare(a.createdAt) },
      }}
      toRow={(referral) => ({
        id: referral.id,
        referred: referral.referredEmail,
        referrer: nameOf(referral.referrerId),
        status: referral.status,
        createdAt: fmtDate(referral.createdAt),
      })}
      columns={[
        { key: "referred", header: t("Referred"), kind: "text", size: 260 },
        { key: "referrer", header: t("Referrer"), kind: "text", size: 220 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 130,
          labels: statuses,
          tones: {
            rewarded: "success-light",
            qualified: "info-light",
            attributed: "secondary",
            void: "destructive-light",
          },
        },
        { key: "createdAt", header: t("Created"), kind: "muted", size: 130 },
      ]}
      facet={{ key: "status", label: t("Status"), values: statuses }}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      searchLabel={t("Search referrals")}
      emptyIcon={<GiftIcon />}
      emptyTitle={t("No referrals found")}
      emptyDescription={t(
        "Referrals appear when someone signs up with a code.",
      )}
    />
  );
}
