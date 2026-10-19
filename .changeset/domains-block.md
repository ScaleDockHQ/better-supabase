---
"better-supabase": minor
---

New block `better-supabase/blocks/domains` (`better-supabase add domains`): the hostnames an organization serves your app on. A custom domain is verified by a DNS TXT record that `createDomainsAdmin().verify()` looks up over DNS-over-HTTPS, and with `blocks.domains.options.platformDomain` set, one label below your domain is a subdomain verified when added (checked against `reserved-slugs` when that module is installed). Each organization has at most one primary hostname, only one organization can hold a verified hostname, and `resolve(host)` returns the organization behind a request's `Host` header for the proxy. The `access` module adds `domains.read` (admins and members) and `domains.manage` (admins); re-run `better-supabase sql sync` to pick up the new default permissions.
