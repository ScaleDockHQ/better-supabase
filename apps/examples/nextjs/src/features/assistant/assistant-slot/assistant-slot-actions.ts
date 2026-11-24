"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { getModels } from "../assistant-queries";
import { durableAvailable } from "../assistant-server";

/**
 * What the shell's assistant panel needs when it opens: the models the caller
 * may use and whether durable answers are available. The shell prerenders
 * without them, so the panel asks on the first open.
 */
export const loadAssistantSlot = bsbCore.action(
  { input: v.object({}), requireTenant: true, permission: "ai_chat.create" },
  async () => ok({ models: await getModels(), durable: durableAvailable() }),
);
