import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Verify your email" };

export default function VerifyEmailPage() {
  return (
    <div className="text-center">
      <h1 className="text-xl font-semibold text-foreground">Check your email</h1>
      <p className="mt-2 text-sm text-foreground-muted">
        We sent a confirmation link to the address you signed up with. Click it to activate your
        account, then log in.
      </p>
      <Link href="/login" className="mt-6 inline-block text-sm font-medium text-accent hover:underline">
        Back to log in
      </Link>
    </div>
  );
}
