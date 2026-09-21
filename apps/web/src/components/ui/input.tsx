import { type InputHTMLAttributes, forwardRef } from "react";

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className = "", ...props }, ref) => {
    return (
      <input
        ref={ref}
        className={`h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent disabled:opacity-50 ${className}`}
        {...props}
      />
    );
  },
);
Input.displayName = "Input";

export function Label({ className = "", ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return (
    <label
      className={`mb-1.5 block text-sm font-medium text-foreground-muted ${className}`}
      {...props}
    />
  );
}

export function FormError({ children }: { children?: string | null }) {
  if (!children) return null;
  return (
    <p role="alert" className="mt-2 rounded-md border border-danger/30 bg-danger-muted px-3 py-2 text-sm text-danger">
      {children}
    </p>
  );
}
