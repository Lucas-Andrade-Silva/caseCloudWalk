import { forwardRef, type ButtonHTMLAttributes } from "react";
import { Kbd } from "./Kbd";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md";

const VARIANTS: Record<Variant, string> = {
  primary: "bg-accent text-on-accent hover:bg-accent-strong",
  secondary: "border border-line bg-surface text-text shadow-card hover:bg-elevated",
  ghost: "text-muted hover:bg-elevated hover:text-text",
  danger: "border border-danger/40 text-danger hover:bg-danger/10",
};

const SIZES: Record<Size, string> = {
  sm: "h-7 gap-1.5 px-2.5 text-xs",
  md: "h-9 gap-2 px-3.5 text-sm",
};

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  /** Ação em andamento: desabilita e avisa leitores de tela. */
  busy?: boolean;
  /** Atalho de teclado mostrado dentro do botão (só exibição). */
  shortcut?: string;
}

// Botão único da plataforma. `forwardRef` para funcionar como gatilho do Radix (`asChild`).
export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "secondary", size = "md", busy = false, shortcut, type = "button", disabled, className = "", children, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      disabled={disabled || busy}
      aria-busy={busy || undefined}
      className={`inline-flex shrink-0 items-center justify-center rounded-lg font-medium whitespace-nowrap transition-colors duration-150 disabled:pointer-events-none disabled:opacity-40 ${VARIANTS[variant]} ${SIZES[size]} ${className}`}
      {...rest}
    >
      {busy && <span aria-hidden className="size-3 animate-spin rounded-full border-2 border-current border-t-transparent" />}
      {children}
      {shortcut && <Kbd tone={variant === "primary" ? "on-accent" : "default"}>{shortcut}</Kbd>}
    </button>
  );
});
