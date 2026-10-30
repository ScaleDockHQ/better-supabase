import { describe, expect, it } from "vitest";

import { toFhirBundle } from "../../src/fhir/bundle.ts";
import { toFhirPatient } from "../../src/fhir/people.ts";

const patient = toFhirPatient({ id: "client-1", name: "Anna" });
const anonymous = { resourceType: "Basic" } as const;

describe("toFhirBundle", () => {
  it("collects resources, with full URLs under a base", () => {
    expect(
      toFhirBundle([patient, anonymous], {
        id: "bundle-1",
        baseUrl: "https://example.com/fhir/",
        timestamp: Temporal.Instant.from("2026-10-30T12:00:00Z"),
      }),
    ).toEqual({
      resourceType: "Bundle",
      id: "bundle-1",
      type: "collection",
      timestamp: "2026-10-30T12:00:00Z",
      entry: [
        {
          fullUrl: "https://example.com/fhir/Patient/client-1",
          resource: patient,
        },
        { resource: anonymous },
      ],
    });
  });

  it("counts a searchset and marks its matches", () => {
    expect(toFhirBundle([patient], { type: "searchset" })).toEqual({
      resourceType: "Bundle",
      type: "searchset",
      total: 1,
      entry: [{ resource: patient, search: { mode: "match" } }],
    });
  });

  it.each(["transaction", "batch"] as const)(
    "puts resources with an id in a %s and posts the rest",
    (type) => {
      expect(toFhirBundle([patient, anonymous], { type }).entry).toEqual([
        {
          resource: patient,
          request: { method: "PUT", url: "Patient/client-1" },
        },
        { resource: anonymous, request: { method: "POST", url: "Basic" } },
      ]);
    },
  );

  it("leaves out the entries of an empty bundle", () => {
    expect(toFhirBundle([])).toEqual({
      resourceType: "Bundle",
      type: "collection",
    });
  });
});
