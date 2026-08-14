import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** دمج أصناف Tailwind مع حل التعارضات — يستخدمه shadcn/ui وكل مكوناتنا. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
