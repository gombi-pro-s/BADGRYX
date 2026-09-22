import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/session";
import { AcceptInviteButton } from "./accept-invite-button";

export const metadata: Metadata = { title: "Accept invitation" };

export default async function AcceptInvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const user = await getCurrentUser();
  if (!user) {
    redirect(`/login?next=${encodeURIComponent(`/invite/${token}`)}`);
  }

  return (
    <div className="mx-auto max-w-md px-6 py-16 text-center">
      <h1 className="text-xl font-semibold text-foreground">Join organization</h1>
      <p className="mt-2 text-sm text-foreground-muted">
        You&apos;ve been invited to join an organization on iCorePen, signed in as{" "}
        <span className="font-medium text-foreground">{user.email}</span>. Accepting adds you as a member and
        lets that organization&apos;s instructors see your real progress.
      </p>
      <div className="mt-6">
        <AcceptInviteButton token={token} />
      </div>
    </div>
  );
}
