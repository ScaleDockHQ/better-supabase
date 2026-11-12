import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  DecisionLog,
  DecisionLogSkeleton,
} from "@/features/guardrails/components/decision-log";
import {
  PolicyGrid,
  PolicyGridSkeleton,
} from "@/features/guardrails/components/policy-grid";
import { PolicyTester } from "@/features/guardrails/components/policy-tester";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const ensureStatic = "prefetch";
export const instant = true;

export default function GuardrailsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/guardrails">) {
  const t = useExtracted("guardrails");

  return (
    <>
      <PageHeader
        title={t("Guardrails")}
        description={t(
          "What each agent may receive and say: injection checks, personal data, denied topics and a tool depth limit. Every check lands in the decision log.",
        )}
      />
      <Suspense fallback={<PolicyGridSkeleton />}>
        <PermissionGate permission="ai_chat.manage">
          <PolicyGrid />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={null}>
        <PermissionGate permission="ai_chat.manage">
          <PolicyTester />
        </PermissionGate>
      </Suspense>
      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-medium">{t("Decision log")}</h2>
        <Suspense fallback={<DecisionLogSkeleton />}>
          <PermissionGate permission="ai_chat.manage">
            <DecisionLog query={loadOpsList(searchParams)} />
          </PermissionGate>
        </Suspense>
      </section>
    </>
  );
}
