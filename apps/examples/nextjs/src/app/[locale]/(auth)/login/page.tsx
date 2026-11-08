import { LoginForm } from "@/features/auth/components/login-form";

// The sign-in form is the static shell (tests/loading-sequences.spec.ts).
export const instant = true;

export default function LoginPage() {
  return <LoginForm />;
}
