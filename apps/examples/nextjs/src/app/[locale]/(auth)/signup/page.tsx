import { SignupForm } from "@/features/auth/components/signup-form";

// The sign-up form is the static shell (tests/loading-sequences.spec.ts).
export const instant = true;

export default function SignupPage() {
  return <SignupForm />;
}
