import "server-only";
import { registerTelemetry } from "ai";
import { meterTelemetry } from "better-supabase/ai-sdk";
import { generatedOptions } from "better-supabase/blocks";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { createUsage } from "better-supabase/blocks/usage";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

let registered = false;

/**
 * Meters every model call's tokens on the tenant's usage meters
 * (`ai.input_tokens`, `ai.output_tokens`), keyed by the `org:` gateway tag the
 * assistant sets. Runs once per process, from `instrumentation.ts`.
 */
export function registerAiTelemetry(): void {
  if (registered) {
    return;
  }

  registered = true;
  registerTelemetry(
    meterTelemetry({
      usage: createUsage({
        ...generatedOptions(blockConfig.usage),
        transport: rpcTransport(bsb.admin().$client, {
          schema: blockConfig.usage.api,
        }),
      }),
      onError: (error) => {
        console.error(`AI usage was not recorded: ${error.message}`);
      },
    }),
  );
}
