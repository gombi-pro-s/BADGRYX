import Link, { type LinkProps } from "next/link";
import type { AnchorHTMLAttributes } from "react";
import { buttonClasses, type ButtonSize, type ButtonVariant } from "./button";

export interface ButtonLinkProps
  extends LinkProps,
    Omit<AnchorHTMLAttributes<HTMLAnchorElement>, keyof LinkProps> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

/** A Link styled like <Button>, rendered as a single <a> -- never a <button> nested inside an <a>. */
export function ButtonLink({
  className = "",
  variant = "primary",
  size = "md",
  ...props
}: ButtonLinkProps) {
  return <Link className={buttonClasses(variant, size, className)} {...props} />;
}
