import { Suspense } from "react";

import {
  SigningKeysRotation,
  SigningKeysRotationSkeleton,
} from "@/features/signing-keys/components/signing-keys-rotation";

export default function SigningKeysSettingsPage() {
  return (
    <Suspense fallback={<SigningKeysRotationSkeleton />}>
      <SigningKeysRotation />
    </Suspense>
  );
}
