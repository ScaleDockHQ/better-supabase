# 0182: Advisories tracks vulnerabilities for a software vendor and publishes CSAF and OpenVEX

- Status: accepted
- Date: 2026-11-01

## Context

The EU Cyber Resilience Act asks a software vendor to track vulnerabilities in
its products, report actively exploited ones and publish security advisories.
`incidents` covers the reporting and `risks` the assessment, but nothing held
products, bills of materials or the advisory itself.

## Decision

A new `advisories` block keeps products and versions, the components of a
CycloneDX 1.4 to 1.7 BOM per version, tracked vulnerabilities, OpenVEX
statements and CSAF 2.0 advisories. Entities and events carry the `advisory_`
or `vulnerability` prefix so they do not collide with other blocks.

Vulnerabilities are enriched on an hourly schedule from OSV, EPSS and the CISA
KEV catalog through a `VulnerabilityFeed` port: `apiVersion: 1`, over `fetch`,
injectable, with a testing kit (`testVulnerabilityFeed`). The block bundles no
vulnerability data and no list of its own. Enrichment never replaces text a
person entered. `vulnerability.exploited` fires when KEV lists an id for the
first time.

CVSS 3.0 and 3.1 vectors are scored. A CVSS 4.0 vector is validated and stored
without a score, because its score comes from a lookup table the block does not
carry. Exposure matches the BOM against affected packages by package URL and
not by version range.

Advisories are drafts until published; each publication raises the CSAF
revision and adds a history entry. `renderCsaf` and `createCsafHandler` serve
the documents from `/.well-known/csaf` over the service role, unsigned.
`renderOpenVex` writes OpenVEX 0.2.0.

Links to `incidents` (`reported_as`) and `risks` (`tracked_as`) are relations
kinds, added only when those blocks are installed. They are integrations and
not requirements. The new spec versions are pinned in `SPEC_PINS`.

## Consequences

- Version range matching and CVSS 4.0 scoring are open; both are additive.
- A vendor with a vulnerability mirror passes its own feed.
- The handler is public, so it must be mounted for one organization.
- Nothing here files a CRA report; the app links the incident.
