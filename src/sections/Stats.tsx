import Counter from "@/components/effects/Counter";
import Reveal from "@/components/effects/Reveal";

const stats = [
  { value: 120, suffix: "+", label: "مشروع مكتمل" },
  { value: 98, suffix: "%", label: "رضا العملاء" },
  { value: 45, suffix: "+", label: "مشروع تخرج بامتياز" },
  { value: 5, suffix: "", label: "سنوات خبرة" },
];

export default function Stats() {
  return (
    <section className="relative border-y border-white/5 bg-gradient-to-l from-violet-950/40 via-[#0b0b12] to-fuchsia-950/30 py-20">
      <div className="mx-auto grid max-w-6xl grid-cols-2 gap-10 px-5 md:grid-cols-4 md:px-10">
        {stats.map((s, i) => (
          <Reveal key={s.label} delay={i * 0.1} className="text-center">
            <div className="font-display text-5xl font-black md:text-6xl">
              <Counter to={s.value} suffix={s.suffix} className="text-gradient" />
            </div>
            <p className="mt-3 text-sm font-medium text-white/55 md:text-base">{s.label}</p>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
