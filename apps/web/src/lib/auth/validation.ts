import { z } from "zod";

export const emailSchema = z.email("Enter a valid email address.");

export const passwordSchema = z
  .string()
  .min(12, "Password must be at least 12 characters.")
  .regex(/[A-Z]/, "Password must include an uppercase letter.")
  .regex(/[a-z]/, "Password must include a lowercase letter.")
  .regex(/[0-9]/, "Password must include a number.");
