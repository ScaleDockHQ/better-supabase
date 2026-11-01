---
"better-supabase": minor
---

New `advisories` block (`better-supabase/blocks/advisories`) for software vendors: products and versions with CycloneDX SBOM import, vulnerabilities enriched hourly from OSV, EPSS and the CISA KEV catalog through the versioned `VulnerabilityFeed` port, OpenVEX statements, and CSAF 2.0 advisories with a `/.well-known/csaf` handler. `testVulnerabilityFeed` in `better-supabase/testing` checks a feed. CVSS 3.x vectors are scored; 4.0 vectors are parsed but not scored. Run `better-supabase upgrade` to add the tables and the `advisories.*` permissions.
