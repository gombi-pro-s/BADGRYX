import { type ButtonHTMLAttributes, forwardRef } from "react";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
export type ButtonSize = "sm" | "md" | "lg";

const variantClasses: Record<ButtonVariant, string> = {
  primary:
    "bg-accent text-accent-foreground hover:opacity-90 focus-visible:outline-accent disabled:opacity-50",
  secondary:
    "bg-surface-raised text-foreground border border-border hover:border-border-strong disabled:opacity-50",
  ghost: "text-foreground-muted hover:text-foreground hover:bg-background-subtle disabled:opacity-50",
  danger: "bg-danger text-white hover:opacity-90 disabled:opacity-50",
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: "h-8 px-3 text-sm",
  md: "h-10 px-4 text-sm",
  lg: "h-11 px-5 text-base",
};

/**
 * Shared visual classes for anything styled like a button, including
 * ButtonLink (an <a>, not a <button>) -- interactive content must never be
 * nested inside an <a> (invalid HTML, breaks assistive tech), so a Link that
 * should look like a button applies these classes directly rather than
 * wrapping <Button>.
 */
export function buttonClasses(variant: ButtonVariant = "primary", size: ButtonSize = "md", className = "") {
  return `inline-flex items-center justify-center gap-2 rounded-md font-medium transition-colors disabled:cursor-not-allowed ${variantClasses[variant]} ${sizeClasses[size]} ${className}`;
}

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className = "", variant = "primary", size = "md", ...props }, ref) => {
    return <button ref={ref} className={buttonClasses(variant, size, className)} {...props} />;
  },
);
Button.displayName = "Button";
