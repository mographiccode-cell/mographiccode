import { motion } from "framer-motion";
import Reveal from "@/components/effects/Reveal";
import { MessagesSquare, PenTool, Code, PartyPopper } from "lucide-react";

const steps = [
  {
    icon: MessagesSquare,
    num: "٠١",
    title: "نستمع ونحلل",
    desc: "جلسة مجانية نفهم فيها هدفك، جمهورك، ومتطلباتك بدقة قبل كتابة سطر واحد.",
  },
  {
    icon: PenTool,
    num: "٠٢",
    title: "نصمم ونبتكر",
    desc: "تصور بصري أولي تشارك فيه برأيك، ونعدّل حتى يصبح التصميم كما تخيلته تمامًا.",
  },
  {
    icon: Code,
    num: "٠٣",
    title: "ننفذ باحتراف",
    desc: "كود نظيف، اختبارات دقيقة، وتحديثات دورية تصلك أولًا بأول طوال فترة التنفيذ.",
  },
  {
    icon: PartyPopper,
    num: "٠٤",
    title: "تسليم ودعم",
    desc: "تسليم كامل مع شرح وافٍ، ودعم فني بعد التسليم لأن نجاحك لا ينتهي عند الاستلام.",
  },
];

export default function Process() {
  return (
    <section id="process" className="relative overflow-hidden py-28">
      <div className="absolute inset-y-0 right-1/2 w-px translate-x-1/2 bg-gradient-to-b from-transparent via-white/10 to-transparent" />

      <div className="relative mx-auto max-w-5xl px-5 md:px-10">
        <Reveal className="mb-20 text-center">
          <p className="mb-3 text-sm font-bold tracking-widest text-violet-300">— آلية العمل</p>
          <h2 className="font-display text-4xl font-black leading-tight md:text-5xl">
            من الفكرة إلى الإطلاق في <span className="text-gradient">أربع خطوات</span>
          </h2>
        </Reveal>

        <div className="space-y-14">
          {steps.map((s, i) => (
            <Reveal key={s.num} delay={0.05}>
              <div className={`relative flex items-center gap-8 md:gap-14 ${i % 2 ? "md:flex-row-reverse" : ""}`}>
                {/* node on the line */}
                <motion.div
                  initial={{ scale: 0 }}
                  whileInView={{ scale: 1 }}
                  viewport={{ once: true }}
                  transition={{ type: "spring", stiffness: 260, damping: 16, delay: 0.2 }}
                  className="absolute right-1/2 hidden size-14 translate-x-1/2 place-items-center rounded-2xl border border-white/15 bg-[#0b0b12] shadow-xl shadow-violet-900/40 md:grid"
                >
                  <s.icon className="size-6 text-violet-300" />
                </motion.div>

                <div className={`w-full md:w-[calc(50%-4rem)] ${i % 2 ? "md:text-right" : "md:text-left"}`}>
                  <div className="glass rounded-3xl p-7 transition-colors duration-500 hover:bg-white/[0.06]">
                    <span className="font-display text-5xl font-black text-white/8">{s.num}</span>
                    <h3 className="font-display mt-2 text-2xl font-bold">{s.title}</h3>
                    <p className="mt-3 leading-relaxed text-white/55">{s.desc}</p>
                  </div>
                </div>
                <div className="hidden md:block md:w-[calc(50%-4rem)]" />
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
