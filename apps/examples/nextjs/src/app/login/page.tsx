import { LoginForm } from '@/features/user/components/login-form';

export const instant = true;

export default function LoginPage() {
  return (
    <main>
      <h1>Sign in</h1>
      <LoginForm />
    </main>
  );
}
