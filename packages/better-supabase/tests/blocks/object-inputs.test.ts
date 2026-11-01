import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

import { closingIndex, mask } from "../../src/cli/sql/config-edit.ts";

const BLOCKS = join(import.meta.dirname, "../../src/blocks");

/**
 * Method signatures that keep several positional arguments on purpose, as
 * `<path under src/blocks>:<method>`: ports other libraries implement,
 * infrastructure backends, callbacks and standard APIs (ADR 0196). A new block
 * client method takes one object, so this list does not grow.
 */
const POSITIONAL = new Set<string>([
  "advisories/feed.ts:epss",
  "advisories/feed.ts:osv",
  "agent-checkout/x402.ts:onVerified",
  "agent-checkout/x402.ts:settle",
  "agent-checkout/x402.ts:verify",
  "ai-evals/job.ts:task",
  "banking/berlin-group.ts:transactions",
  "content/seo.ts:translationUrlFor",
  "e-prescribing/e-prescribing.ts:cancel",
  "e-prescribing/e-prescribing.ts:deliver",
  "maintenance/telemetry.ts:meterFor",
  "activities/recordings.ts:summarize",
  "activities/recordings.ts:transcribe",
  "ai-files/types.ts:createSignedUrl",
  "ai-files/types.ts:upload",
  "api-keys/api-keys.ts:Partial",
  "assets/record-binding.ts:load",
  "attachments/attachments.ts:createSignedUrl",
  "attachments/attachments.ts:getPublicUrl",
  "attachments/attachments.ts:publicUrl",
  "attachments/attachments.ts:scan",
  "attachments/attachments.ts:signedUrl",
  "attachments/attachments.ts:upload",
  "attachments/client.ts:open",
  "attachments/client.ts:setRequestHeader",
  "attachments/list-controller.ts:onMessage",
  "attachments/record-binding.ts:load",
  "attachments/record-binding.ts:run",
  "audit/audit-log.ts:createSignedUrl",
  "audit/audit-log.ts:upload",
  "audit/audit.ts:between",
  "audit/audit.ts:purge",
  "audit/csv.ts:formatRow",
  "automations/automations.ts:onOutcomes",
  "automations/client.ts:change",
  "automations/conversion.ts:create",
  "automations/conversion.ts:map",
  "banking/feed.ts:transactions",
  "billable-time/record-binding.ts:load",
  "billable-time/record-binding.ts:run",
  "bulk/bulk.ts:async",
  "clinical-decision-support/clinical-decision-support.ts:evaluate",
  "comments/client.ts:onMessage",
  "comments/record-binding.ts:count",
  "comments/record-binding.ts:copy",
  "custom-fields/record-binding.ts:copy",
  "custom-fields/record-binding.ts:load",
  "custom-fields/record-binding.ts:run",
  "drive/record-binding.ts:load",
  "drive/record-binding.ts:run",
  "field-history/record-binding.ts:load",
  "reactions/record-binding.ts:load",
  "reactions/record-binding.ts:run",
  "record-bindings.ts:copy",
  "signatures/record-binding.ts:load",
  "tags/record-binding.ts:copy",
  "comments/record-binding.ts:load",
  "comments/record-binding.ts:run",
  "contracts/record-binding.ts:load",
  "courses/record-binding.ts:load",
  "courses/record-binding.ts:run",
  "create-blocks.ts:call",
  "create-blocks.ts:client",
  "create-blocks.ts:on",
  "create-blocks.ts:portOf",
  "created-by/extension.ts:beforeMutation",
  "data-lifecycle/data-lifecycle.ts:createSignedUrl",
  "data-lifecycle/data-lifecycle.ts:list",
  "data-lifecycle/data-lifecycle.ts:upload",
  "data-lifecycle/importer.ts:start",
  "data-lifecycle/importer.ts:upsertBatch",
  "dispatch/record-binding.ts:load",
  "dispatch/record-binding.ts:run",
  "donations/record-binding.ts:load",
  "drive/changes.ts:nodeOf",
  "drive/documents.ts:nodeOf",
  "drive/documents.ts:nodesOf",
  "drive/extract.ts:extract",
  "drive/preview.ts:render",
  "employees/actions.ts:map",
  "enrollments/record-binding.ts:load",
  "flags/flags.ts:getBooleanDetails",
  "flags/flags.ts:getNumberDetails",
  "flags/flags.ts:getObjectDetails",
  "flags/flags.ts:getStringDetails",
  "flags/flags.ts:onEvaluate",
  "flags/flags.ts:resolveBooleanEvaluation",
  "flags/flags.ts:resolveNumberEvaluation",
  "flags/flags.ts:resolveObjectEvaluation",
  "flags/flags.ts:resolveStringEvaluation",
  "flags/flags.ts:roles",
  "funding/funding.ts:poll",
  "funding/funding.ts:render",
  "funding/funding.ts:send",
  "guests/record-binding.ts:load",
  "guests/record-binding.ts:run",
  "imports/app-table-import.ts:upsert",
  "imports/define-import.ts:finish",
  "imports/define-import.ts:insert",
  "imports/define-import.ts:upsertBatch",
  "inbox/client.ts:onEvent",
  "inbox/client.ts:onMessage",
  "inbox/client.ts:send",
  "invoices/collections.ts:invoice",
  "invoices/open-items.ts:invoice",
  "knowledge/knowledge.ts:embed",
  "knowledge/knowledge.ts:extract",
  "leases/record-binding.ts:load",
  "ledger/record-binding.ts:load",
  "mail-sync/providers.ts:get",
  "mail-sync/providers.ts:post",
  "medications/medications.ts:get",
  "medications/medications.ts:search",
  "memberships/extension.ts:beforeMutation",
  "memberships/extension.ts:context",
  "memberships/extension.ts:transformQuery",
  "messaging/client.ts:onMessage",
  "messaging/messaging.ts:read",
  "messaging/messaging.ts:save",
  "messaging/summaries.ts:read",
  "messaging/summaries.ts:save",
  "metrics/manifest.ts:sink",
  "moderation/record-binding.ts:load",
  "notifications/api-types.ts:hydrate",
  "notifications/api-types.ts:render",
  "notifications/client.ts:onMessage",
  "notifications/client.ts:sort",
  "notifications/delivery.ts:send",
  "notifications/transports/resend.ts:send",
  "notifications/watcher-sink.ts:data",
  "oauth-server/oauth-server.ts:isRevoked",
  "orders/actions.ts:create",
  "outbox/outbox.ts:async",
  "outbox/outbox.ts:onError",
  "passes/record-binding.ts:load",
  "passes/record-binding.ts:run",
  "permissions/authorizer.ts:evaluations",
  "permissions/authorizer.ts:forOperation",
  "permissions/authorizer.ts:once",
  "push/push.ts:onTickets",
  "push/push.ts:send",
  "queue/backends.ts:advance",
  "queue/backends.ts:advanceSchedule",
  "queue/backends.ts:async",
  "queue/backends.ts:dueSchedules",
  "queue/backends.ts:extend",
  "queue/backends.ts:fail",
  "queue/backends.ts:listDead",
  "queue/backends.ts:purge",
  "queue/backends.ts:read",
  "queue/backends.ts:replay",
  "queue/backends.ts:retryDead",
  "queue/backends.ts:rpc",
  "queue/backends.ts:schedule",
  "queue/backends.ts:send",
  "queue/backends.ts:sendOnce",
  "queue/dead-letters.ts:listDead",
  "queue/dead-letters.ts:onDead",
  "queue/dead-letters.ts:retryDead",
  "queue/idempotency.ts:begin",
  "queue/idempotency.ts:complete",
  "queue/idempotency.ts:extend",
  "queue/idempotency.ts:release",
  "queue/lease.ts:acquire",
  "queue/lease.ts:extend",
  "queue/lease.ts:release",
  "queue/types.ts:onError",
  "queue/types.ts:onFinish",
  "queue/vercel-queue.ts:handler",
  "queue/vercel-queue.ts:onReceive",
  "queue/vercel-queue.ts:receive",
  "queue/vercel-queue.ts:retry",
  "queue/vercel-queue.ts:send",
  "queue/vercel-route.ts:handleCallback",
  "queue/vercel-route.ts:handleNodeCallback",
  "queue/vercel-route.ts:onError",
  "queue/vercel-route.ts:retry",
  "queue/webhook-inbox.ts:handler",
  "queue/webhook-inbox.ts:verify",
  "quotes/actions.ts:create",
  "reactions/client.ts:onMessage",
  "record-bindings.ts:column",
  "record-bindings.ts:count",
  "record-bindings.ts:load",
  "record-bindings.ts:optimistic",
  "record-bindings.ts:run",
  "relations/record-binding.ts:load",
  "relations/record-binding.ts:run",
  "reminders/schedule.ts:markSent",
  "rename-block.ts:count",
  "rename-block.ts:load",
  "rename-block.ts:optimistic",
  "saved-views/client.ts:SavedViewsSnapshot",
  "saved-views/client.ts:onApplyState",
  "saved-views/client.ts:setPreference",
  "scores/record-binding.ts:load",
  "security-events/receiver.ts:setStatus",
  "security-events/receiver.ts:verify",
  "sessions/client.ts:approveAuthorization",
  "sessions/client.ts:denyAuthorization",
  "settings/client.ts:set",
  "settings/client.ts:setField",
  "share-links/record-binding.ts:load",
  "share-links/record-binding.ts:run",
  "shipments/carrier.ts:cancel",
  "shipments/carrier.ts:createLabel",
  "shipments/carrier.ts:rates",
  "shipments/carrier.ts:track",
  "shipments/record-binding.ts:load",
  "shipments/record-binding.ts:run",
  "signing-keys/signing-keys.ts:signJwt",
  "sla/record-binding.ts:load",
  "sla/record-binding.ts:run",
  "sso/scim-store.ts:delete",
  "sso/scim-store.ts:get",
  "sso/scim-store.ts:list",
  "sso/scim-store.ts:save",
  "stripe.ts:constructEventAsync",
  "stripe.ts:create",
  "stripe.ts:createTaxId",
  "stripe.ts:deleteTaxId",
  "stripe.ts:listTaxIds",
  "stripe.ts:new",
  "stripe.ts:update",
  "tags/record-binding.ts:load",
  "tags/record-binding.ts:run",
  "tasks/actions.ts:map",
  "tasks/record-binding.ts:load",
  "templates/merge-fields.ts:format",
  "templates/merge-fields.ts:render",
  "templates/recurring.ts:enqueueOnce",
  "templates/templates.ts:apply",
  "timeline/timeline.ts:describe",
  "trash/extension.ts:beforeMutation",
  "trash/extension.ts:restore",
  "trash/extension.ts:transformQuery",
  "updated-at/extension.ts:beforeMutation",
  "upload-claim.ts:claimSignedUpload",
  "vercel-marketplace/vercel-marketplace.ts:async",
  "vercel-marketplace/vercel-marketplace.ts:onError",
  "versions/record-binding.ts:load",
  "versions/record-binding.ts:run",
  "webhooks/encoders.ts:encode",
  "webhooks/outgoing.ts:async",
  "webhooks/secrets.ts:rotate",
  "webhooks/url-policy.ts:lookup",
  "webhooks/verify.ts:handler",
  "workflow-editor/executor.ts:approval",
]);

function files(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      return files(path);
    }

    return /\.tsx?$/.test(entry.name) && !entry.name.endsWith(".d.ts")
      ? [path]
      : [];
  });
}

const SIGNATURE =
  /^[ \t]*(?:(?:public|private|protected|static|readonly|async)\s+)*([A-Za-z_$][\w$]*)\??\s*(?::\s*)?(?:<[^()]*>)?\(/gm;

/** How many top-level parameters the parenthesis at `open` holds. */
function parameterCount(code: string, close: number, open: number): number {
  const body = code.slice(open + 1, close);
  let depth = 0;
  let commas = 0;

  for (const char of body) {
    if ("([{<".includes(char)) {
      depth += 1;
    } else if (")]}>".includes(char)) {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      commas += 1;
    }
  }

  const trailing = /,\s*$/.test(body);

  return body.trim().length === 0 ? 0 : commas + 1 - (trailing ? 1 : 0);
}

/** The `<file>:<method>` of every signature in `src/blocks` with 2+ parameters. */
function multiParameter(): string[] {
  const found = new Set<string>();

  for (const file of files(BLOCKS)) {
    const code = mask(readFileSync(file, "utf-8"));

    for (const match of code.matchAll(SIGNATURE)) {
      const open = match.index + match[0].length - 1;
      const close = closingIndex(code, open);

      if (close === -1) {
        continue;
      }

      const after = /^\s*(\S+)/.exec(code.slice(close + 1))?.[1] ?? "";

      // A signature or a definition with a return type; a call has none.
      if (!after.startsWith(":") && !after.startsWith("=>")) {
        continue;
      }

      if (parameterCount(code, close, open) >= 2) {
        found.add(`${relative(BLOCKS, file)}:${match[1]}`);
      }
    }
  }

  return [...found].toSorted();
}

describe("block client methods", () => {
  it("take one object, except the listed ports", () => {
    const unexpected = multiParameter().filter((name) => !POSITIONAL.has(name));

    expect(unexpected).toEqual([]);
  });

  it("lists no exception that no longer applies", () => {
    const found = new Set(multiParameter());

    expect([...POSITIONAL].filter((name) => !found.has(name))).toEqual([]);
  });
});
