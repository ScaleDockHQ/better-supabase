import { getExtracted } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";

import {
  getAgentCounts,
  getApprovalInbox,
  getRunPage,
} from "../agents-queries";

const EVERYTHING = { q: "", filter: null, sort: null, cursor: null } as const;

/**
 * Render inside `<Suspense>` with `AgentsKpiBandSkeleton`: the figures of the
 * agents, run queue or approval inbox overview.
 */
export async function AgentsKpiBand({
  kind,
}: {
  kind: "agents" | "runs" | "approvals";
}) {
  const t = await getExtracted("agents");

  switch (kind) {
    case "agents": {
      const counts = await getAgentCounts();

      return (
        <KpiBand
          kpis={[
            { label: t("Your agents"), value: String(counts.mine) },
            { label: t("Shared"), value: String(counts.shared) },
            { label: t("Installed"), value: String(counts.installed) },
            { label: t("Tools in use"), value: String(counts.tools) },
          ]}
        />
      );
    }

    case "runs": {
      const page = await getRunPage(EVERYTHING);
      const plus = page.capped ? "+" : "";

      return (
        <KpiBand
          kpis={[
            {
              label: t("Running"),
              value: `${page.counts.running + page.counts.queued}${plus}`,
              href: "/assistant/agents/runs?filter=running",
            },
            {
              label: t("Failed"),
              value: `${page.counts.failed}${plus}`,
              href: "/assistant/agents/runs?filter=failed",
            },
            {
              label: t("Completed"),
              value: `${page.counts.completed}${plus}`,
              href: "/assistant/agents/runs?filter=completed",
            },
            {
              label: t("Cancelled"),
              value: `${page.counts.cancelled}${plus}`,
              href: "/assistant/agents/runs?filter=cancelled",
            },
          ]}
        />
      );
    }

    case "approvals": {
      const inbox = await getApprovalInbox(EVERYTHING);

      return (
        <KpiBand
          kpis={[
            { label: t("Waiting"), value: String(inbox.items.length) },
            { label: t("Tools asking"), value: String(inbox.tools.length) },
            {
              label: t("Chats waiting"),
              value: String(new Set(inbox.items.map((row) => row.chatId)).size),
            },
          ]}
        />
      );
    }

    default: {
      const unreachable: never = kind;

      return unreachable;
    }
  }
}

export function AgentsKpiBandSkeleton() {
  return <KpiBandSkeleton />;
}
