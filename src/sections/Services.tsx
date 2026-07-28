import { GraduationCap, Palette, Code2, Rocket, ArrowUpLeft } from "lucide-react";
import SpotlightCard from "@/components/effects/SpotlightCard";
import Reveal from "@/components/effects/Reveal";

const services = [
  {
    icon: GraduationCap,
    title: "مشاريع التخرج",
    desc: "من الفكرة إلى المناقشة: تحليل، برمجة، توثيق أكاديمي، وعرض تقديمي يليق بسنوات دراستك. دعم كامل حتى يوم التسليم.",
    tags: ["برمجة كاملة", "توثيق", "عرض تقديمي"],
    gradient: "from-violet-500/20 to-transparent",
    iconColor: "text-violet-300",
    ring: "group-hover:border-violet-400/40",
  },
  {
    icon: Palette,
    title: "التصميم الجرافيكي",
    desc: "هويات بصرية، شعارات، منشورات سوشيال ميديا، ومواد تسويقية تُميّز علامتك وتعلق في ذاكرة جمهورك.",
    tags: ["هوية بصرية", "شعارات", "سوشيال ميديا"],
    gradient: "from-fuchsia-500/20 to-transparent",
    iconColor: "text-fuchsia-300",
    ring: "group-hover:border-fuchsia-400/40",
  },
  {
    icon: Code2,
    title: "برامج مخصصة",
    desc: "أنظمة إدارية، تطبيقات ويب وموبايل، وحلول أتمتة مبنية خصيصًا حول احتياج عملك — لا قوالب جاهزة.",
    tags: ["أنظمة إدارية", "تطبيقات", "أتمتة"],
    gradient: "from-cyan-500/20 to-transparent",
    iconColor: "text-cyan-300",
    ring: "group-hover:border-cyan-400/40",
  },
  {
    icon: Rocket,
    title: "صفحات الهبوط",
    desc: "صفحات بصرية ساحرة بسرعة تحميل فائقة، مصممة نفسيًا وتقنيًا لتحويل الزائر إلى عميل يدفع.",
    tags: ["تحويل عالٍ", "سرعة", "SEO"],
    gradient: "from-amber-500/20 to-transparent",
    iconColor: "text-amber-300",
    ring: "group-hover:border-amber-400/40",
  },
];

export default function Services() {
  return (
    <section id="services" className="relative mx-auto max-w-7xl px-5 py-28 md:px-10">
      <div className="absolute top-40 left-0 size-[400px] rounded-full bg-violet-700/10 blur-[140px]" />

      <Reveal className="mb-16 max-w-2xl">
        <p className="mb-3 text-sm font-bold tracking-widest text-fuchsia-300">— ماذا أقدم</p>
        <h2 className="font-display text-4xl font-black leading-tight md:text-5xl">
          أربع خدمات، <span className="text-gradient">هدف واحد:</span> نجاحك
        </h2>
        <p className="mt-5 text-lg leading-relaxed text-white/55">
          كل خدمة تُنفَّذ بمعايير احترافية صارمة: بحث، تصميم، تنفيذ، ومراجعة — حتى آخر بكسل.
        </p>
      </Reveal>

      <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
        {services.map((s, i) => (
          <Reveal key={s.title} delay={i * 0.1}>
            <SpotlightCard
              className={`h-full rounded-3xl border border-white/8 bg-white/[0.03] p-7 transition-all duration-500 hover:-translate-y-2 hover:bg-white/[0.05] ${s.ring}`}
            >
              <div className={`absolute -top-16 -left-16 size-40 rounded-full bg-gradient-to-br ${s.gradient} blur-2xl`} />
              <div className="relative">
                <div className="mb-6 grid size-14 place-items-center rounded-2xl border border-white/10 bg-white/5">
                  <s.icon className={`size-7 ${s.iconColor}`} />
                </div>
                <h3 className="font-display text-xl font-bold">{s.title}</h3>
                <p className="mt-3 text-sm leading-relaxed text-white/55">{s.desc}</p>
                <div className="mt-5 flex flex-wrap gap-2">
                  {s.tags.map((t) => (
                    <span key={t} className="rounded-full border border-white/10 px-3 py-1 text-xs text-white/60">
                      {t}
                    </span>
                  ))}
                </div>
                <div className="mt-6 flex items-center gap-1.5 text-sm font-bold text-white/40 transition-colors group-hover:text-white">
                  اطلب الخدمة
                  <ArrowUpLeft className="size-4 transition-transform duration-300 group-hover:-translate-x-0.5 group-hover:-translate-y-0.5" />
                </div>
              </div>
            </SpotlightCard>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
