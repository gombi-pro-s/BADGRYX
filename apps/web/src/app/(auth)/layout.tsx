import Link from "next/link";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background-subtle px-4 py-12">
      <div className="mb-8">
        <Link href="/" className="font-mono text-lg font-semibold tracking-tight text-foreground">
          iCore<span className="text-accent">Pen</span>
        </Link>
      </div>
      <div className="w-full max-w-sm rounded-lg border border-border bg-surface p-8 shadow-sm">
        {children}
      </div>
    </div>
  );
}
