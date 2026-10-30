import type { FhirResource } from "better-supabase/fhir";

import {
  toFhirBundle,
  toFhirCarePlan,
  toFhirConsent,
  toFhirMedicationRequest,
  toFhirObservation,
} from "better-supabase/fhir";

import { bsb } from "../../../../../lib/supabase/server";

/**
 * `GET /api/customers/:id/fhir`: the customer's care plans, observations,
 * medication orders and consents as one FHIR R4 `collection` Bundle.
 */
export const GET = bsb.route<{ id: string }, true>(
  async (_request, { db, params, tenant: organizationId }) => {
    const subject = { type: "customer", id: params.id };

    const [summaries, observations, definitions, orders, consents] =
      await Promise.all([
        db.carePlans.list(subject.type, subject.id),
        db.observations.list(subject.type, subject.id),
        db.observations.definitions(organizationId),
        db.medications.ordersOf(subject),
        db.consents.list(subject),
      ]);

    if (!summaries.ok) {
      return summaries;
    }

    if (!observations.ok) {
      return observations;
    }

    if (!definitions.ok) {
      return definitions;
    }

    if (!orders.ok) {
      return orders;
    }

    if (!consents.ok) {
      return consents;
    }

    const plans = await Promise.all(
      summaries.data.map((summary) => db.carePlans.get(summary.id)),
    );

    const failed = plans.find((plan) => !plan.ok);

    if (failed) {
      return failed;
    }

    const byKey = new Map(
      definitions.data.map((definition) => [definition.key, definition]),
    );

    const resources: FhirResource[] = [
      ...plans.flatMap((plan) => (plan.ok ? [toFhirCarePlan(plan.data)] : [])),
      ...observations.data.map((observation) => {
        const definition = byKey.get(observation.definitionKey);

        return toFhirObservation(observation, definition ? { definition } : {});
      }),
      ...orders.data.map((order) => toFhirMedicationRequest(order)),
      ...consents.data.map((consent) => toFhirConsent(consent)),
    ];

    return Response.json(toFhirBundle(resources), {
      headers: {
        "content-type": "application/fhir+json",
        "cache-control": "no-store",
      },
    });
  },
  { requireTenant: true, permission: "customers.read" },
);
