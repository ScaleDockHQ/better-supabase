import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { AiSchedules } from "better-supabase/blocks/ai-schedules";

import { generatedOptions } from "better-supabase/blocks";
import {
  createAiSchedules,
  rpcTransport,
} from "better-supabase/blocks/ai-schedules";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["ai-schedules"].api;

/**
 * The ai-schedules block acting as the caller. The service role sets each new
 * task's next run right after the save, instead of on the next tick.
 */
export function aiTasks(supabase: RpcClient): AiSchedules {
  return createAiSchedules({
    ...generatedOptions(blockConfig["ai-schedules"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: rpcTransport(bsb.admin().$client, { schema: API_SCHEMA }),
  });
}
