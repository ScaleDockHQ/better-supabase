import {
  BuildingIcon,
  FileSignatureIcon,
  HeartPulseIcon,
  ListOrderedIcon,
  TargetIcon,
  UsersRoundIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { BlockListQuery } from "@/lib/array-list";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { CreateContactDialog } from "@/features/crm/components/create-contact-dialog";
import { loadContacts, settle } from "@/features/crm/crm-queries";

import {
  loadHealth,
  loadQueues,
  loadScoreModels,
  loadSegments,
} from "../automation/automation-queries";
import { loadContracts } from "../revenue/revenue-queries";
import {
  createContract,
  createQueue,
  createScoreModel,
  createSegment,
} from "../sales-actions";
import { ActionDialog } from "./action-dialog";
import { BlockOverview } from "./block-overview";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

export function SalesListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}

const LIFECYCLES = [
  "lead",
  "mql",
  "sql",
  "opportunity",
  "customer",
  "churned",
] as const;

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreateSegmentDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createSegment}
      title={t("New segment")}
      description={t(
        "A segment keeps the companies that match its rule and refreshes on a schedule.",
      )}
      trigger={t("New segment")}
      submitLabel={t("Create segment")}
      successMessage={t("Segment created")}
      redirectTo="/crm/segments/{id}"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        { name: "description", label: t("Description"), kind: "textarea" },
        {
          name: "lifecycle",
          label: t("Lifecycle stage is"),
          kind: "select",
          options: LIFECYCLES.map((value) => ({ value, label: value })),
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SegmentOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("segments.read");

  const [t, loaded, fmtDate, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(loadSegments),
    dateFormatter(),
    holds("segments.write"),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (segment) => `${segment.name} ${segment.description ?? ""}`,
        facet: (segment) => segment.subjectType,
        defaultSort: "name",
        sorts: {
          name: (a, b) => a.name.localeCompare(b.name),
          members: (a, b) => b.memberCount - a.memberCount,
        },
      }}
      toRow={(segment) => ({
        id: segment.id,
        name: segment.name,
        subjectType: segment.subjectType,
        members: segment.memberCount,
        rules: segment.rules,
        refreshedAt: segment.refreshedAt ? fmtDate(segment.refreshedAt) : null,
      })}
      columns={[
        {
          key: "name",
          header: t("Segment"),
          kind: "link",
          href: "/crm/segments/{id}",
          size: 260,
        },
        { key: "subjectType", header: t("Records"), kind: "badge", size: 120 },
        { key: "members", header: t("Members"), kind: "number", size: 100 },
        { key: "rules", header: t("Rules"), kind: "number", size: 80 },
        {
          key: "refreshedAt",
          header: t("Last refresh"),
          kind: "muted",
          size: 150,
        },
      ]}
      facet={{
        key: "subjectType",
        label: t("Records"),
        values: {
          company: t("Companies"),
          person: t("People"),
          deal: t("Deals"),
        },
      }}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "members", label: t("Most members") },
      ]}
      searchLabel={t("Search segments")}
      errorTitle={t("The segments didn't load")}
      emptyIcon={<UsersRoundIcon />}
      emptyTitle={t("No segments found")}
      emptyDescription={t("Save a filter over companies as a segment.")}
      emptyAction={canWrite ? <CreateSegmentDialog /> : undefined}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreateQueueDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createQueue}
      title={t("New queue")}
      description={t(
        "A queue picks an owner for each new record, in turn or by weight.",
      )}
      trigger={t("New queue")}
      submitLabel={t("Create queue")}
      successMessage={t("Queue created")}
      redirectTo="/crm/queues/{id}"
      fields={[
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "subjectType",
          label: t("Assigns"),
          kind: "select",
          options: [
            { value: "company", label: t("Companies") },
            { value: "person", label: t("People") },
            { value: "deal", label: t("Deals") },
          ],
        },
        {
          name: "strategy",
          label: t("Strategy"),
          kind: "select",
          options: [
            { value: "round_robin", label: t("Round robin") },
            { value: "weighted", label: t("Weighted") },
          ],
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function QueueOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("assignment.read");

  const [t, loaded, canManage] = await Promise.all([
    getExtracted("sales"),
    settle(loadQueues),
    holds("assignment.manage"),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (queue) => queue.name,
        facet: (queue) => queue.strategy,
        defaultSort: "rank",
        sorts: {
          rank: (a, b) => a.rank - b.rank,
          name: (a, b) => a.name.localeCompare(b.name),
          assigned: (a, b) => b.assigned - a.assigned,
        },
      }}
      toRow={(queue) => ({
        id: queue.id,
        name: queue.name,
        subjectType: queue.subjectType,
        strategy: queue.strategy,
        members: queue.members,
        assigned: queue.assigned,
        state: queue.enabled ? "enabled" : "paused",
      })}
      columns={[
        {
          key: "name",
          header: t("Queue"),
          kind: "link",
          href: "/crm/queues/{id}",
          size: 240,
        },
        { key: "subjectType", header: t("Assigns"), kind: "badge", size: 120 },
        {
          key: "strategy",
          header: t("Strategy"),
          kind: "badge",
          size: 140,
          labels: { round_robin: t("Round robin"), weighted: t("Weighted") },
        },
        { key: "members", header: t("Members"), kind: "number", size: 100 },
        { key: "assigned", header: t("Assigned"), kind: "number", size: 100 },
        {
          key: "state",
          header: t("State"),
          kind: "badge",
          size: 110,
          labels: { enabled: t("Enabled"), paused: t("Paused") },
          tones: { enabled: "success-light", paused: "warning-light" },
        },
      ]}
      facet={{
        key: "strategy",
        label: t("Strategy"),
        values: { round_robin: t("Round robin"), weighted: t("Weighted") },
      }}
      sorts={[
        { value: "rank", label: t("Order") },
        { value: "name", label: t("Name") },
        { value: "assigned", label: t("Most assigned") },
      ]}
      searchLabel={t("Search queues")}
      errorTitle={t("The queues didn't load")}
      emptyIcon={<ListOrderedIcon />}
      emptyTitle={t("No queues found")}
      emptyDescription={t("Create a queue to route new records to your team.")}
      emptyAction={canManage ? <CreateQueueDialog /> : undefined}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreateScoreModelDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createScoreModel}
      title={t("New score model")}
      description={t(
        "A model gives points to the companies that match its rules.",
      )}
      trigger={t("New model")}
      submitLabel={t("Create model")}
      successMessage={t("Model created")}
      redirectTo="/crm/scoring/{id}"
      fields={[
        {
          name: "key",
          label: t("Key"),
          kind: "text",
          required: true,
          placeholder: "lead",
        },
        { name: "name", label: t("Name"), kind: "text", required: true },
        {
          name: "lifecycle",
          label: t("Points for lifecycle stage"),
          kind: "select",
          options: LIFECYCLES.map((value) => ({ value, label: value })),
        },
        {
          name: "points",
          label: t("Points"),
          kind: "number",
          required: true,
          defaultValue: "10",
        },
      ]}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ScoreModelOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("scores.read");

  const [t, loaded, canManage] = await Promise.all([
    getExtracted("sales"),
    settle(loadScoreModels),
    holds("scores.manage"),
  ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (model) => `${model.name} ${model.key}`,
        facet: (model) => model.subjectType,
        defaultSort: "name",
        sorts: { name: (a, b) => a.name.localeCompare(b.name) },
      }}
      toRow={(model) => ({
        id: model.id,
        name: model.name,
        key: model.key,
        subjectType: model.subjectType,
        rules: model.rules,
        metrics: model.metrics,
        bands: model.bands,
        version: model.version,
        state: model.enabled ? "enabled" : "paused",
      })}
      columns={[
        {
          key: "name",
          header: t("Model"),
          kind: "link",
          href: "/crm/scoring/{id}",
          size: 220,
        },
        { key: "key", header: t("Key"), kind: "muted", size: 120 },
        { key: "subjectType", header: t("Scores"), kind: "badge", size: 110 },
        { key: "rules", header: t("Rules"), kind: "number", size: 80 },
        { key: "metrics", header: t("Metrics"), kind: "number", size: 90 },
        { key: "bands", header: t("Bands"), kind: "muted", size: 180 },
        { key: "version", header: t("Version"), kind: "number", size: 90 },
        {
          key: "state",
          header: t("State"),
          kind: "badge",
          size: 110,
          labels: { enabled: t("Enabled"), paused: t("Paused") },
          tones: { enabled: "success-light", paused: "warning-light" },
        },
      ]}
      facet={{
        key: "subjectType",
        label: t("Scores"),
        values: { company: t("Companies"), person: t("People") },
      }}
      sorts={[{ value: "name", label: t("Name") }]}
      searchLabel={t("Search models")}
      errorTitle={t("The score models didn't load")}
      emptyIcon={<TargetIcon />}
      emptyTitle={t("No score models found")}
      emptyDescription={t("Create a model to rank leads and accounts.")}
      emptyAction={canManage ? <CreateScoreModelDialog /> : undefined}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CreateContractDialog() {
  const t = await getExtracted("sales");

  return (
    <ActionDialog
      action={createContract}
      title={t("New contract")}
      trigger={t("New contract")}
      submitLabel={t("Create draft")}
      successMessage={t("Contract drafted")}
      redirectTo="/crm/contracts/{id}"
      fields={[
        { name: "title", label: t("Title"), kind: "text", required: true },
        {
          name: "value",
          label: t("Value"),
          kind: "decimal",
          placeholder: "24000.00",
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
        { name: "startsOn", label: t("Starts"), kind: "date" },
        { name: "endsOn", label: t("Ends"), kind: "date" },
        {
          name: "autoRenew",
          label: t("Renews automatically"),
          kind: "select",
          options: [
            { value: "no", label: t("No") },
            { value: "yes", label: t("Yes") },
          ],
        },
      ]}
    />
  );
}

export async function contractStatusLabels(): Promise<
  Readonly<Record<string, string>>
> {
  const t = await getExtracted("sales");

  return {
    draft: t("Draft"),
    in_review: t("In review"),
    out_for_signature: t("Out for signature"),
    active: t("Active"),
    expired: t("Expired"),
    terminated: t("Terminated"),
  };
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ContractOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("contracts.read");

  const [t, loaded, fmtMoney, fmtDate, statusLabels, canWrite] =
    await Promise.all([
      getExtracted("sales"),
      settle(loadContracts),
      moneyFormatter(),
      dateFormatter(),
      contractStatusLabels(),
      holds("contracts.write"),
    ]);

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (contract) => contract.title,
        facet: (contract) => contract.status,
        defaultSort: "ending",
        sorts: {
          ending: (a, b) =>
            (a.endsOn ?? "9999").localeCompare(b.endsOn ?? "9999"),
          notice: (a, b) =>
            (a.noticeDeadline ?? "9999").localeCompare(
              b.noticeDeadline ?? "9999",
            ),
          title: (a, b) => a.title.localeCompare(b.title),
        },
      }}
      toRow={(contract) => ({
        id: contract.id,
        title: contract.title,
        status: contract.status,
        value: contract.value ? fmtMoney(contract.value) : null,
        startsOn: fmtDate(contract.startsOn),
        endsOn: fmtDate(contract.endsOn),
        notice: fmtDate(contract.noticeDeadline),
        renews: contract.autoRenew ? "auto" : "manual",
      })}
      columns={[
        {
          key: "title",
          header: t("Contract"),
          kind: "link",
          href: "/crm/contracts/{id}",
          size: 280,
        },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 150,
          labels: statusLabels,
          tones: {
            active: "success-light",
            out_for_signature: "info-light",
            in_review: "warning-light",
            expired: "destructive-light",
            terminated: "destructive-light",
          },
        },
        { key: "value", header: t("Value"), kind: "number", size: 130 },
        { key: "startsOn", header: t("Starts"), kind: "muted", size: 120 },
        { key: "endsOn", header: t("Ends"), kind: "muted", size: 120 },
        { key: "notice", header: t("Notice by"), kind: "muted", size: 120 },
        {
          key: "renews",
          header: t("Renewal"),
          kind: "badge",
          size: 110,
          labels: { auto: t("Automatic"), manual: t("Manual") },
        },
      ]}
      facet={{ key: "status", label: t("Status"), values: statusLabels }}
      sorts={[
        { value: "ending", label: t("Ending soonest") },
        { value: "notice", label: t("Notice deadline") },
        { value: "title", label: t("Title") },
      ]}
      searchLabel={t("Search contracts")}
      errorTitle={t("The contracts didn't load")}
      emptyIcon={<FileSignatureIcon />}
      emptyTitle={t("No contracts found")}
      emptyDescription={t("Draft a contract, or change the filters.")}
      emptyAction={canWrite ? <CreateContractDialog /> : undefined}
    />
  );
}

// skeleton: the page's Suspense fallback is the skeleton of this view
export async function HealthOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("scores.read");

  const [t, loaded, fmtDate] = await Promise.all([
    getExtracted("sales"),
    settle(loadHealth),
    dateFormatter(),
  ]);

  const rows =
    loaded.kind === "ok"
      ? ({ kind: "ok", data: loaded.data.rows } as const)
      : loaded;

  const bands = Object.fromEntries(
    (loaded.kind === "ok" ? loaded.data.rows : [])
      .flatMap((row) => (row.band ? [row.band] : []))
      .map((band) => [band, band]),
  );

  return (
    <BlockOverview
      loaded={rows}
      query={query}
      spec={{
        search: (row) => `${row.name} ${row.band ?? ""}`,
        facet: (row) => row.band ?? "",
        defaultSort: "lowest",
        sorts: {
          lowest: (a, b) => a.score - b.score,
          highest: (a, b) => b.score - a.score,
          name: (a, b) => a.name.localeCompare(b.name),
        },
      }}
      toRow={(row) => ({
        id: row.subjectId,
        name: row.name,
        score: row.score,
        band: row.band,
        computedAt: fmtDate(row.computedAt),
      })}
      columns={[
        {
          key: "name",
          header: t("Account"),
          kind: "link",
          href: "/crm/contacts/{id}",
          size: 280,
        },
        { key: "score", header: t("Score"), kind: "number", size: 100 },
        { key: "band", header: t("Band"), kind: "badge", size: 120 },
        { key: "computedAt", header: t("Scored"), kind: "muted", size: 140 },
      ]}
      facet={{ key: "band", label: t("Band"), values: bands }}
      sorts={[
        { value: "lowest", label: t("Lowest score first") },
        { value: "highest", label: t("Highest score first") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search accounts")}
      errorTitle={t("Account health didn't load")}
      emptyIcon={<HeartPulseIcon />}
      emptyTitle={t("No scored accounts yet")}
      emptyDescription={t(
        "Create a score model for companies and score them to see which accounts need attention.",
      )}
    />
  );
}

/**
 * Companies and people, searched, filtered by lifecycle and paged on the
 * server.
 */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ContactOverview({ query }: { query: BlockListQuery }) {
  await requirePermission("contacts.read");

  const [t, loaded, canWrite] = await Promise.all([
    getExtracted("sales"),
    settle(loadContacts),
    holds("contacts.write"),
  ]);

  const lifecycles = {
    lead: t("Lead"),
    mql: t("Marketing qualified"),
    sql: t("Sales qualified"),
    opportunity: t("Opportunity"),
    customer: t("Customer"),
    churned: t("Churned"),
    prospect: t("Prospect"),
  };

  const suppliers = {
    approved: t("Approved"),
    conditional: t("Conditional"),
    blocked: t("Blocked"),
  };

  return (
    <BlockOverview
      loaded={loaded}
      query={query}
      spec={{
        search: (contact) => `${contact.name} ${contact.detail ?? ""}`,
        facet: (contact) => contact.lifecycle,
        defaultSort: "name",
        sorts: {
          name: (a, b) => a.name.localeCompare(b.name),
          lifecycle: (a, b) =>
            a.lifecycle.localeCompare(b.lifecycle) ||
            a.name.localeCompare(b.name),
        },
      }}
      toRow={(contact) => ({
        id: contact.id,
        name: contact.name,
        kind: contact.kind,
        detail: contact.detail,
        lifecycle: contact.lifecycle,
        supplier: contact.supplierStatus,
      })}
      columns={[
        {
          key: "name",
          header: t("Name"),
          kind: "link",
          href: "/crm/contacts/{id}",
          size: 280,
        },
        {
          key: "kind",
          header: t("Type"),
          kind: "badge",
          size: 110,
          labels: { company: t("Company"), person: t("Person") },
        },
        {
          key: "detail",
          header: t("Email or domain"),
          kind: "muted",
          size: 260,
        },
        {
          key: "lifecycle",
          header: t("Lifecycle"),
          kind: "badge",
          size: 150,
          labels: lifecycles,
        },
        {
          key: "supplier",
          header: t("Supplier"),
          kind: "badge",
          size: 120,
          labels: suppliers,
          tones: {
            approved: "success-light",
            conditional: "warning-light",
            blocked: "destructive-light",
          },
        },
      ]}
      facet={{ key: "lifecycle", label: t("Lifecycle"), values: lifecycles }}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "lifecycle", label: t("Lifecycle") },
      ]}
      searchLabel={t("Search contacts")}
      errorTitle={t("The contacts didn't load")}
      emptyIcon={<BuildingIcon />}
      emptyTitle={t("No contacts found")}
      emptyDescription={t(
        "Add the companies you sell to and the people you talk to.",
      )}
      emptyAction={canWrite ? <CreateContactDialog /> : undefined}
    />
  );
}
