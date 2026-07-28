const row1 = ["مشاريع تخرج", "هوية بصرية", "صفحات هبوط", "برامج مخصصة", "تصميم شعارات", "واجهات مستخدم", "أنظمة إدارية", "موشن جرافيك"];
const row2 = ["React", "Figma", "Flutter", "Photoshop", "Node.js", "Illustrator", "Laravel", "After Effects", "Tailwind", "MySQL"];

function Strip({ items, reverse = false }: { items: string[]; reverse?: boolean }) {
  const doubled = [...items, ...items, ...items];
  return (
    <div className="mask-fade-x flex overflow-hidden">
      <div className={`flex shrink-0 items-center gap-6 py-5 pl-6 ${reverse ? "animate-marquee-rev" : "animate-marquee"}`}>
        {doubled.map((item, i) => (
          <span key={i} className="flex items-center gap-6 whitespace-nowrap">
            <span className={`font-display text-2xl font-bold md:text-3xl ${i % 2 ? "text-stroke" : "text-white/85"}`}>
              {item}
            </span>
            <span className="size-2 rotate-45 bg-gradient-to-br from-violet-400 to-fuchsia-400" />
          </span>
        ))}
      </div>
    </div>
  );
}

export default function Marquee() {
  return (
    <section className="relative border-y border-white/5 bg-white/[0.015]">
      <Strip items={row1} />
      <div className="h-px bg-white/5" />
      <Strip items={row2} reverse />
    </section>
  );
}
