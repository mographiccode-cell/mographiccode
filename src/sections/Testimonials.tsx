import Reveal from "@/components/effects/Reveal";
import SpotlightCard from "@/components/effects/SpotlightCard";
import { Quote, Star } from "lucide-react";

const testimonials = [
  {
    name: "سارة العتيبي",
    role: "خريجة علوم حاسب",
    text: "مشروع التخرج كان حلم صار حقيقة. التوثيق والبرمجة والعرض كل شيء كان متكامل، وحصلت على امتياز مع مرتبة الشرف.",
    color: "from-violet-500 to-fuchsia-500",
  },
  {
    name: "محمد الشهري",
    role: "صاحب متجر إلكتروني",
    text: "صفحة الهبوط رفعت مبيعاتي بنسبة ٦٠٪ خلال أول شهر. تصميم يجنن وسرعة تحميل خيالية — يستاهل كل ريال.",
    color: "from-cyan-500 to-blue-500",
  },
  {
    name: "نورة القحطاني",
    role: "مديرة تسويق",
    text: "الهوية البصرية اللي صممها لنا غيّرت نظرة العملاء للعلامة بالكامل. إبداع حقيقي والتزام بالمواعيد نادر.",
    color: "from-amber-500 to-rose-500",
  },
];

export default function Testimonials() {
  return (
    <section id="testimonials" className="relative mx-auto max-w-7xl px-5 py-28 md:px-10">
      <div className="absolute bottom-20 right-0 size-[380px] rounded-full bg-fuchsia-700/10 blur-[140px]" />

      <Reveal className="mb-14 text-center">
        <p className="mb-3 text-sm font-bold tracking-widest text-amber-300">— آراء العملاء</p>
        <h2 className="font-display text-4xl font-black leading-tight md:text-5xl">
          كلماتهم <span className="text-gradient">أصدق من وصفنا</span>
        </h2>
      </Reveal>

      <div className="grid gap-5 md:grid-cols-3">
        {testimonials.map((t, i) => (
          <Reveal key={t.name} delay={i * 0.12}>
            <SpotlightCard className="flex h-full flex-col rounded-3xl border border-white/8 bg-white/[0.03] p-7 transition-all duration-500 hover:-translate-y-2">
              <Quote className="size-8 text-white/15" />
              <p className="mt-4 flex-1 leading-relaxed text-white/70">{t.text}</p>
              <div className="mt-6 flex items-center gap-1">
                {Array.from({ length: 5 }).map((_, s) => (
                  <Star key={s} className="size-4 fill-amber-400 text-amber-400" />
                ))}
              </div>
              <div className="mt-5 flex items-center gap-3 border-t border-white/8 pt-5">
                <span className={`grid size-11 place-items-center rounded-full bg-gradient-to-br ${t.color} font-display text-lg font-bold text-white`}>
                  {t.name[0]}
                </span>
                <div>
                  <p className="font-bold">{t.name}</p>
                  <p className="text-sm text-white/45">{t.role}</p>
                </div>
              </div>
            </SpotlightCard>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
