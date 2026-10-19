---
"better-supabase": minor
---

Create, the config and the CLI now offer the same conventions under the same names.

`init` and `apply` take `--casing`, `--scope`, `--tenant-name`, `--access`, `--id-type` and `--api`. With a preset, a flag changes that field and the CLI writes the new preset code, so `preset info` and Create still read it. Without a preset, `init` writes the matching config keys, and it asks for each convention in Create's order and with Create's labels; `--yes` and CI use the defaults. `casing` defaults to `snake` everywhere, as it does on Create. With `--access provider`, `init` writes the same `authorization` comment Create's config does.

`apply` takes `--package`, and both commands read `package=` from a Create URL. A URL with `authz=` prints a note that the authorization library isn't part of the preset.

`plugins.tenant.column` and the tenant column of a subject without `tenant` now default to `<sql.naming.tenant>_id`, such as `workspace_id`, instead of always `organization_id`. Set the column to keep the old name.

The config check now rejects what the types reject: a `json` entry without `import` or `type`, a malformed bucket (`path`, `policy`, `lifecycle`) and an unknown `sql.workflow`. `schemas/config-v1.json` is generated from the same schema, so the editor checks match the CLI, and it drops `triggerPrefix` and `disabled.tenantKey`, which the config never read.
