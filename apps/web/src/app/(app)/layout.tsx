import Link from "next/link";
import { getUserRoles, requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "../(auth)/actions";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/skills", label: "Skill Graph" },
  { href: "/settings", label: "Settings" },
];

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const supabase = await createClient();
  const [{ data: profile }, roles] = await Promise.all([
    supabase.from("profiles").select("display_name, username").eq("id", user.id).single(),
    getUserRoles(user.id),
  ]);
  const isAdmin = roles.includes("admin");
  const navItems = isAdmin ? [...NAV_ITEMS, { href: "/admin", label: "Admin" }] : NAV_ITEMS;

  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 flex-col border-r border-border bg-surface md:flex">
        <div className="flex h-16 items-center border-b border-border px-5">
          <Link href="/dashboard" className="font-mono text-base font-semibold tracking-tight">
            iCore<span className="text-accent">Pen</span>
          </Link>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-md px-3 py-2 text-sm font-medium text-foreground-muted transition-colors hover:bg-background-subtle hover:text-foreground"
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="border-t border-border p-3">
          <div className="mb-2 truncate px-3 text-sm text-foreground-muted">
            {profile?.display_name ?? user.email}
          </div>
          <form action={signOutAction}>
            <button
              type="submit"
              className="w-full rounded-md px-3 py-2 text-left text-sm font-medium text-foreground-muted hover:bg-background-subtle hover:text-foreground"
            >
              Log out
            </button>
          </form>
        </div>
      </aside>
      <main className="flex-1 bg-background-subtle">{children}</main>
    </div>
  );
}
