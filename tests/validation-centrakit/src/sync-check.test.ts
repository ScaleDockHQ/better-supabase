import { introspect, run, serializeSnapshot } from "better-supabase/cli";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, withCentraKit } from "./stack.ts";

const live = await reachable();
const fixture = fileURLToPath(new URL("..", import.meta.url));

describe("the committed module files", () => {
  // The first command loads the CLI from source, which takes about 5 s on a
  // CI runner.
  it(
    "are what upgrade writes for the config and the provider snapshot",
    { timeout: 30_000 },
    async () => {
      const result = await run(["upgrade", "--check", "--cwd", fixture]);

      expect(result).toMatchObject({ code: 0, stderr: "" });
    },
  );
});

describe.skipIf(!live)("doctor on the installed fixture", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("reports only findings about CentraKit's own schema and config", async () => {
    const dir = await mkdtemp(join(tmpdir(), "centrakit-doctor-"));

    try {
      await withCentraKit(pool, async (s) => {
        await s.as("service");

        const snapshot = await introspect(s.client, [
          "centrakit",
          "better_supabase",
        ]);

        await writeFile(
          join(dir, "snapshot.json"),
          serializeSnapshot(snapshot),
        );
      });

      // BS303 compares the app's generated client with the database; the
      // fixture has no app code to generate. BS700 and BS701 report the
      // host's shared memory, which other local stacks fill.
      const result = await run([
        "doctor",
        "--json",
        "--ignore",
        "BS303,BS700,BS701",
        "--snapshot",
        join(dir, "snapshot.json"),
        "--cwd",
        fixture,
      ]);

      const { data: report } = JSON.parse(result.stdout) as {
        readonly data: {
          readonly findings: readonly {
            readonly code: string;
            readonly severity: string;
            readonly message: string;
            readonly target?: string;
          }[];
        };
      };

      // Every warning left is about CentraKit's own tables, functions and
      // config, which the fixture keeps as the app wrote them. The shared
      // stack also has the Next.js example's comments and reactions modules,
      // which the fixture doesn't install, so doctor BS213 doesn't know
      // comments.deleted_at is a soft-delete column.
      const warnings: Record<string, string[]> = {};

      for (const finding of report.findings) {
        if (
          finding.severity !== "info" &&
          !(
            finding.code === "BS213" &&
            finding.message.includes("reaction_subject_visible")
          ) &&
          // The attachments upgrade drops the old create_attachment overloads;
          // the schema migration that creates the new one isn't in this project.
          !(
            finding.code === "BS235" &&
            finding.message.includes("create_attachment")
          )
        ) {
          (warnings[`${finding.severity} ${finding.code}`] ??= []).push(
            finding.target ?? "",
          );
        }
      }

      for (const targets of Object.values(warnings)) {
        targets.sort();
      }

      expect(warnings).toEqual({
        // CentraKit grants projects to members for select only.
        "warning BS107": ["centrakit.projects"],
        // CentraKit's schema grants select on every table, including ones it keeps
        // closed to authenticated with no policy.
        "warning BS115": [
          "centrakit.audit_log_restricted_details",
          "centrakit.contact_profiles",
          "centrakit.employees",
          "centrakit.field_definitions",
          "centrakit.field_options",
          "centrakit.field_values",
          "centrakit.file_node_grant",
          "centrakit.import_runs",
          "centrakit.inbound_webhook_events",
          "centrakit.inbound_webhooks",
          "centrakit.integration_credentials",
          "centrakit.organization_number_sequences",
          "centrakit.organization_tags",
          "centrakit.recurrence_rules",
          "centrakit.reminder_deliveries",
          "centrakit.reminders",
          "centrakit.roles",
          "centrakit.share_links",
          "centrakit.subject_user_state",
          "centrakit.subject_views",
          "centrakit.task_tags",
          "centrakit.user_roles",
          "centrakit.webhook_destination_secrets",
          "centrakit.workflow_events",
          "centrakit.workflow_runs",
        ],
        // CentraKit's own authz helpers, executable through /rpc.
        "warning BS116": [
          "centrakit.authz_can_assign",
          "centrakit.authz_is_platform",
          "centrakit.authz_organization_ids_with",
        ],
        // Tenant columns CentraKit doesn't index.
        "warning BS204": [
          "centrakit.customer_contacts.organization_id",
          "centrakit.customers.organization_id",
          "centrakit.employees.organization_id",
          "centrakit.file_node.organization_id",
          "centrakit.file_node_grant.organization_id",
          "centrakit.inbound_webhook_events.organization_id",
          "centrakit.inbound_webhooks.organization_id",
          "centrakit.integration_credentials.organization_id",
          "centrakit.notification_deliveries.organization_id",
          "centrakit.notification_events.organization_id",
          "centrakit.notification_preferences.organization_id",
          "centrakit.notification_recipients.organization_id",
          "centrakit.organization_users.organization_id",
          "centrakit.projects.organization_id",
          "centrakit.tasks.organization_id",
          "centrakit.webhook_destination_secrets.organization_id",
          "centrakit.workflow_events.organization_id",
          "centrakit.workflow_runs.organization_id",
        ],
        // CentraKit's foreign keys that don't carry organization_id.
        "warning BS217": [
          "centrakit.customer_contacts.customer_contacts_customer_id_fkey",
          "centrakit.file_node_grant.file_node_grant_file_node_id_fkey",
          "centrakit.notification_deliveries.notification_deliveries_recipient_id_fkey",
          "centrakit.notification_recipients.notification_recipients_event_id_fkey",
          "centrakit.projects.projects_customer_id_fkey",
          "centrakit.tasks.tasks_contact_id_fkey",
          "centrakit.tasks.tasks_customer_id_fkey",
          "centrakit.tasks.tasks_project_id_fkey",
          "centrakit.webhook_deliveries.webhook_deliveries_destination_id_fkey",
          "centrakit.webhook_deliveries.webhook_deliveries_event_id_fkey",
          "centrakit.webhook_deliveries.webhook_deliveries_workflow_run_id_fkey",
          "centrakit.webhook_destination_secrets.webhook_destination_secrets_destination_id_fkey",
        ],
        // CentraKit's int8 ids, with no `int8` codec in the config.
        "warning BS222": [
          "centrakit.customer_contacts",
          "centrakit.customers",
          "centrakit.field_values",
          "centrakit.inbound_webhook_events",
          "centrakit.workflow_events",
        ],
        // The adopt options that keep CentraKit's own token storage, secret column,
        // audit values and event sources.
        "warning BS314": [
          "blocks.audit.options.values",
          "blocks.invitations.options.tokenStorage",
          "blocks.outbox.options.blockSource",
          "blocks.outbox.options.defaultSource",
          "blocks.webhooks-out.options.secretStorage",
        ],
        // CentraKit's tables without the audit trigger.
        "warning BS315": [
          "centrakit.contact_profiles",
          "centrakit.customer_contacts",
          "centrakit.customers",
          "centrakit.employees",
          "centrakit.project_members",
          "centrakit.projects",
          "centrakit.roles",
          "centrakit.task_tags",
          "centrakit.tasks",
          "centrakit.user_roles",
          "centrakit.workflow_runs",
        ],
      });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }, 60_000);
});
