import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderModules } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("shared-signals", { modules })!;

const withWebhooks = (modules: AnyBlocksConfig = {}): string =>
  renderModules(["webhooks-out", "shared-signals"], { modules })
    .filter((file) => file.module === "shared-signals")
    .map((file) => file.contents)
    .join("\n");

const SIGNATURES = [
  '"create_ssf_stream"(uuid, text, text, text[], text, text[], text[], text, text, jsonb)',
  '"ssf_stream"(uuid)',
  '"ssf_streams"(text)',
  '"update_ssf_stream"(uuid, jsonb)',
  '"delete_ssf_stream"(uuid)',
  '"queue_ssf_set"(uuid, text, text)',
  '"set_ssf_stream_status"(uuid, text, text)',
  '"ssf_streams_for_event"(text, text)',
  '"poll_ssf_events"(uuid, integer, text[], jsonb)',
  '"note_ssf_verification"(uuid, interval)',
  '"record_ssf_received"(text, text)',
  '"forget_ssf_received"(text, text)',
  '"purge_shared_signals"(interval)',
];

describe("shared-signals module", () => {
  it("keeps every function for the service role", () => {
    const sql = body();
    for (const signature of SIGNATURES) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql.match(/hint = 'SSF_FORBIDDEN'/g)).toHaveLength(
      SIGNATURES.length,
    );
  });

  it("refuses push streams without webhooks-out", () => {
    const sql = body();
    expect(sql).toContain("hint = 'SSF_PUSH_UNAVAILABLE'");
    expect(sql).not.toContain("dispatch_webhook");
  });

  it("creates a set-format endpoint and dispatches through webhooks-out", () => {
    const sql = withWebhooks();
    expect(sql).toContain("'set'");
    expect(sql).toContain('"dispatch_webhook"(');
    expect(sql).toContain("on delete set null");
    expect(sql).not.toContain("hint = 'SSF_PUSH_UNAVAILABLE'");
  });

  it("quotes the retention option as an interval literal", () => {
    const sql = body({
      "shared-signals": { options: { retention: "1 day'; drop table x; --" } },
    });
    expect(sql).toContain("'1 day''; drop table x; --'::interval");
  });
});
