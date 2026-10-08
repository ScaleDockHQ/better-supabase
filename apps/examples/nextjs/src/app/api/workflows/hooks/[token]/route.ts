import { serviceBuilder } from "@/features/workflows/builder/builder-server";

/**
 * Webhook triggers: the token in the path names the trigger, the JSON body
 * is the run's input and `Idempotency-Key` keys the start.
 */
export function POST(request: Request): Promise<Response> {
  return serviceBuilder().triggers.webhook(request);
}
