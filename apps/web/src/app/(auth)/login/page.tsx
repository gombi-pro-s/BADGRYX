import type { Metadata } from "next";
import Link from "next/link";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Log in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; deleted?: string }>;
}) {
  const { next, deleted } = await searchParams;

  return (
    <div>
      <h1 className="text-xl font-semibold text-foreground">Log in</h1>
      <p className="mt-1 text-sm text-foreground-muted">Continue your training.</p>
      {deleted && (
        <div className="mt-4 rounded-md border border-border bg-surface p-3 text-sm text-foreground-muted">
          Your account has been permanently deleted.
        </div>
      )}
      <div className="mt-6">
        <LoginForm next={next} />
      </div>
      <p className="mt-6 text-center text-sm text-foreground-muted">
        No account?{" "}
        <Link href="/signup" className="font-medium text-accent hover:underline">
          Sign up
        </Link>
      </p>
    </div>
  );
}
