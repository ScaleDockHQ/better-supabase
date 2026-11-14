import { Suspense } from "react";

import {
  SigningKeysRotation,
  SigningKeysRotationSkeleton,
} from "@/features/signing-keys/components/signing-keys-rotation";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function SigningKeysSettingsPage() {
  return (
    <Suspense fallback={<SigningKeysRotationSkeleton />}>
      <SigningKeysRotation />
    </Suspense>
  );
}
