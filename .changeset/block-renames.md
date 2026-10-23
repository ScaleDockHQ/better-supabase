---
"better-supabase": minor
---

Breaking: 26 blocks take plain names. The block name changes in the config, the CLI, the subpath (`better-supabase/blocks/<name>`), the exports, the operation names (`<block>.<action>`) and the CloudEvent source (`better-supabase/<block>`). Table names, permission keys, event types, hint codes and queue names don't change. `better-supabase codemod 0.15` renames the config keys, the imports and the subpaths, and lists event sources for review. `better-supabase upgrade` moves the installed blocks to their new names and renames two tables that clashed: hiring's `jobs` becomes `job_openings` and catalog's `collections` becomes `product_collections`. A 0.14 name in the config stops `add` and `gen` with a message that names the codemod.

| 0.14                 | 0.15               |
| -------------------- | ------------------ |
| `work-items`         | `tasks`            |
| `parties`            | `contacts`         |
| `engagements`        | `activities`       |
| `targets`            | `goals`            |
| `number-sequences`   | `numbering`        |
| `actor`              | `created-by`       |
| `ensure-rls`         | `rls-guard`        |
| `shared-signals`     | `security-events`  |
| `service-principals` | `service-accounts` |
| `support-sessions`   | `impersonation`    |
| `controls`           | `compliance`       |
| `ai-tasks`           | `ai-schedules`     |
| `ai-providers`       | `ai-keys`          |
| `workflow-builder`   | `workflow-editor`  |
| `jobs`               | `queue`            |
| `access`             | `permissions`      |
| `rules`              | `automations`      |
| `tenant`             | `memberships`      |
| `activity`           | `timeline`         |
| `workflow-sdk-world` | `workflow-sdk`     |

The docs pages move with their blocks, and `/docs/blocks/<old>` redirects to the new page.
