import TiltCard from "@/components/effects/TiltCard";
import Reveal from "@/components/effects/Reveal";
import { ArrowUpLeft } from "lucide-react";

type Work = {
  title: string;
  category: string;
  year: string;
  art: string;
  accent: string;
  big?: boolean;
};

const works: Work[] = [
  {
    title: "نظام إدارة عيادات ذكي",
    category: "مشروع تخرج — برمجة كاملة",
    year: "2025",
    art: "from-violet-600 via-indigo-600 to-blue-500",
    accent: "bg-violet-400",
    big: true,
  },
  {
    title: "هوية مقهى «رَوّاح»",
    category: "تصميم جرافيكي — هوية بصرية",
    year: "2025",
    art: "from-fuchsia-600 via-pink-500 to-rose-400",
    accent: "bg-fuchsia-400",
  },
  {
    title: "صفحة هبوط لتطبيق مالي",
    category: "صفحة هبوط — تحويل عالٍ",
    year: "2024",
    art: "from-cyan-500 via-teal-500 to-emerald-400",
    accent: "bg-cyan-400",
  },
  {
    title: "برنامج مخازن وفوترة",
    category: "برنامج مخصص — نظام إداري",
    year: "2024",
    art: "from-amber-500 via-orange-500 to-red-400",
    accent: "bg-amber-400",
  },
  {
    title: "منصة تعليمية تفاعلية",
    category: "مشروع تخرج — ويب متكامل",
    year: "2024",
    art: "from-purple-600 via-violet-500 to-fuchsia-400",
    accent: "bg-purple-400",
    big: true,
  },
];

export default function Portfolio() {
  return (
    <section id="work" className="relative mx-auto max-w-7xl px-5 py-28 md:px-10">
      <Reveal className="mb-14 flex flex-wrap items-end justify-between gap-6">
        <div className="max-w-xl">
          <p className="mb-3 text-sm font-bold tracking-widest text-cyan-300">— أعمال مختارة</p>
          <h2 className="font-display text-4xl font-black leading-tight md:text-5xl">
            مشاريع <span className="text-gradient">تتحدث عن نفسها</span>
          </h2>
        </div>
        <p className="max-w-sm text-white/50">
          كل مشروع قصة نجاح: عميل راضٍ، درجة امتياز، أو مبيعات تضاعفت.
        </p>
      </Reveal>

      <div className="grid gap-5 md:grid-cols-3">
        {works.map((w, i) => (
          <Reveal key={w.title} delay={i * 0.08} className={w.big ? "md:col-span-2" : ""}>
            <TiltCard className="group h-full">
              <div className="relative flex h-full min-h-[300px] flex-col justify-end overflow-hidden rounded-3xl border border-white/8 md:min-h-[340px]">
                {/* generated artwork */}
                <div className={`absolute inset-0 bg-gradient-to-br ${w.art} opacity-80 transition-transform duration-700 group-hover:scale-105`} />
                <div
                  className="absolute inset-0 opacity-30"
                  style={{
                    backgroundImage:
                      "radial-gradient(circle at 25% 30%, rgba(255,255,255,.35), transparent 40%), radial-gradient(circle at 80% 75%, rgba(0,0,0,.35), transparent 45%)",
                  }}
                />
                {/* mock window chrome */}
                <div className="absolute inset-x-6 top-6 rounded-t-2xl border border-white/20 bg-black/25 p-3 backdrop-blur-md transition-transform duration-500 group-hover:-translate-y-1">
                  <div className="flex items-center gap-1.5">
                    <span className="size-2.5 rounded-full bg-red-400/80" />
                    <span className="size-2.5 rounded-full bg-amber-400/80" />
                    <span className="size-2.5 rounded-full bg-emerald-400/80" />
                  </div>
                  <div className="mt-3 space-y-2">
                    <div className="h-2 w-3/5 rounded-full bg-white/30" />
                    <div className="h-2 w-4/5 rounded-full bg-white/20" />
                    <div className="h-2 w-2/5 rounded-full bg-white/25" />
                  </div>
                  <div className="mt-4 grid grid-cols-3 gap-2">
                    <div className="h-10 rounded-lg bg-white/15" />
                    <div className="h-10 rounded-lg bg-white/10" />
                    <div className="h-10 rounded-lg bg-white/15" />
                  </div>
                </div>

                {/* bottom info */}
                <div className="relative z-10 flex items-end justify-between gap-4 bg-gradient-to-t from-black/70 to-transparent p-6 pt-20">
                  <div>
                    <div className="mb-2 flex items-center gap-2 text-xs text-white/70">
                      <span className={`size-1.5 rounded-full ${w.accent}`} />
                      {w.category} · {w.year}
                    </div>
                    <h3 className="font-display text-2xl font-bold text-white">{w.title}</h3>
                  </div>
                  <span className="grid size-11 shrink-0 place-items-center rounded-full border border-white/25 bg-white/10 backdrop-blur transition-all duration-300 group-hover:bg-white group-hover:text-black">
                    <ArrowUpLeft className="size-5" />
                  </span>
                </div>
              </div>
            </TiltCard>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
