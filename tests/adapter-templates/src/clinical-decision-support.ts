import type {
  CareDecisionAlert,
  ClinicalDecisionSupport,
} from "better-supabase/blocks/clinical-decision-support";

import type { HttpOptions } from "./http.ts";

import { list, record, requestJson, text } from "./http.ts";

const SEVERITIES = ["info", "warning", "critical"] as const;

/**
 * A `ClinicalDecisionSupport` engine over a drug database service (ADR 0173).
 * It sends the medication codes and returns the alerts the service raises now.
 * Keep each `fingerprint` stable across calls: the same fingerprint updates the
 * alert and keeps a member's decision.
 */
export function createDecisionSupport(
  options: HttpOptions,
): ClinicalDecisionSupport {
  return {
    apiVersion: 1,
    key: "example-drug-database",
    async evaluate(context, request) {
      if (context.medications.length === 0) {
        return [];
      }

      const body = await requestJson(options, "/interactions", {
        method: "POST",
        body: {
          codes: context.medications.map((medication) => ({
            orderId: medication.orderId,
            system: medication.codeSystem,
            code: medication.code,
          })),
        },
        ...(request.signal === undefined ? {} : { signal: request.signal }),
      });

      if (!body.ok) {
        throw new Error(body.error.message);
      }

      return list(record(body.data, "interactions").alerts, "alerts").map(
        (item): CareDecisionAlert => {
          const alert = record(item, "alert");
          const severity = SEVERITIES.find((one) => one === alert.severity);

          return {
            kind: "interaction",
            ...(severity === undefined ? {} : { severity }),
            message: text(alert.message, "alert.message"),
            fingerprint: text(alert.id, "alert.id"),
            orderIds: list(alert.orderIds, "alert.orderIds").map((id) =>
              text(id, "alert.orderIds[]"),
            ),
          };
        },
      );
    },
  };
}
