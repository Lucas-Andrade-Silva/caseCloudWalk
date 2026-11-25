// Foto de cada pessoa de demonstração (retratos de banco de imagens livres, randomuser.me, em public/avatars).
// Quem não tem foto aparece com as iniciais numa cor estável.
const PHOTOS = new Set(["ana", "bruno", "carla", "olivia"]);

const TONES = [
  "bg-accent/15 text-accent-ink",
  "bg-info/15 text-info",
  "bg-warning/15 text-warning-ink",
  "bg-risk/15 text-risk",
  "bg-danger/15 text-danger-ink",
];

export function avatarUrl(name: string): string | null {
  const first = name.trim().split(/\s+/)[0]?.toLowerCase() ?? "";
  return PHOTOS.has(first) ? `/avatars/${first}.jpg` : null;
}

export function Avatar({ name, className = "size-7 rounded-lg" }: { name: string; className?: string }) {
  const url = avatarUrl(name);
  // O nome aparece ao lado: a foto é decorativa.
  if (url) return <img src={url} alt="" className={`shrink-0 object-cover ${className}`} />;
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
  const tone = TONES[[...name].reduce((sum, char) => sum + char.charCodeAt(0), 0) % TONES.length];
  return (
    <span aria-hidden className={`flex shrink-0 items-center justify-center text-[11px] font-semibold ${tone} ${className}`}>
      {initials}
    </span>
  );
}
