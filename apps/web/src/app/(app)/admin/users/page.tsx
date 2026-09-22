import type { Metadata } from "next";
import { requireAdmin } from "@/lib/auth/session";
import { UserSearch } from "./user-search";

export const metadata: Metadata = { title: "Users" };

export default async function AdminUsersPage() {
  const admin = await requireAdmin();

  return (
    <div>
      <h2 className="mb-1 text-lg font-semibold text-foreground">Users</h2>
      <p className="mb-6 text-sm text-foreground-muted">
        Grant or revoke instructor/moderator/admin roles. Every change is audit-logged
        (<code className="rounded bg-background-subtle px-1 py-0.5 text-xs">grant_platform_role()</code> /
        <code className="rounded bg-background-subtle px-1 py-0.5 text-xs">revoke_platform_role()</code>), and you
        can never revoke your own admin role from here.
      </p>
      <UserSearch currentAdminId={admin.id} />
    </div>
  );
}
