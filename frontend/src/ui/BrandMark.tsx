// Marca da plataforma no idioma visual da CloudWalk: mono, minúsculas e o cursor de terminal em verde.
// Não usa o logotipo da CloudWalk: é o nome deste produto.
export function BrandMark({ size = "sm" }: { size?: "sm" | "lg" }) {
  const text = size === "lg" ? "text-xl" : "text-[13px]";
  const cursor = size === "lg" ? "h-5 w-2.5" : "h-3.5 w-[7px]";
  return (
    <span className={`inline-flex items-center gap-0.5 font-mono font-medium tracking-tight text-text ${text}`}>
      helpdesk
      <span aria-hidden className={`inline-block bg-accent motion-safe:animate-[blink_1.1s_steps(1)_infinite] ${cursor}`} />
    </span>
  );
}
