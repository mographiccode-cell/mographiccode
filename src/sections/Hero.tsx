import { motion, useScroll, useTransform } from "framer-motion";
import { ArrowDown, GraduationCap, Palette, Rocket, Code2 } from "lucide-react";
import ParticleField from "@/components/effects/ParticleField";
import MagneticButton from "@/components/effects/MagneticButton";
import { useRef } from "react";

const words = ["فكرتك", "تستحق", "أن", "تُرى", "بشكلٍ", "مختلف"];

const floating = [
  { icon: GraduationCap, label: "مشاريع تخرج", pos: "top-[22%] right-[6%]", delay: "0s", hide: "hidden lg:flex" },
  { icon: Palette, label: "تصميم جرافيكي", pos: "top-[38%] left-[7%]", delay: "1.2s", hide: "hidden lg:flex" },
  { icon: Code2, label: "برامج مخصصة", pos: "bottom-[30%] right-[10%]", delay: "2s", hide: "hidden md:flex" },
  { icon: Rocket, label: "صفحات هبوط", pos: "bottom-[24%] left-[12%]", delay: "0.6s", hide: "hidden md:flex" },
];

export default function Hero() {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const yBg = useTransform(scrollYProgress, [0, 1], [0, 220]);
  const opacity = useTransform(scrollYProgress, [0, 0.7], [1, 0]);

  return (
    <section id="top" ref={ref} className="relative flex min-h-svh items-center justify-center overflow-hidden">
      {/* ambient orbs */}
      <motion.div style={{ y: yBg }} className="absolute inset-0">
        <div className="animate-pulse-glow absolute -top-32 right-[15%] size-[480px] rounded-full bg-violet-600/25 blur-[140px]" />
        <div className="animate-pulse-glow absolute bottom-0 left-[10%] size-[420px] rounded-full bg-fuchsia-600/20 blur-[140px]" style={{ animationDelay: "1.5s" }} />
        <div className="absolute top-1/3 left-1/2 size-[380px] -translate-x-1/2 rounded-full bg-cyan-500/10 blur-[120px]" />
      </motion.div>

      {/* grid backdrop */}
      <div
        className="absolute inset-0 opacity-[0.14]"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,.08) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.08) 1px, transparent 1px)",
          backgroundSize: "72px 72px",
          maskImage: "radial-gradient(ellipse 70% 60% at 50% 45%, black, transparent)",
        }}
      />

      <ParticleField className="absolute inset-0 h-full w-full" />

      {/* floating service chips */}
      {floating.map((f) => (
        <motion.div
          key={f.label}
          initial={{ opacity: 0, scale: 0.6 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 1.4, duration: 0.8, type: "spring" }}
          className={`animate-float absolute ${f.pos} ${f.hide} items-center gap-2 rounded-2xl glass px-4 py-2.5 text-sm font-medium text-white/85 shadow-xl`}
          style={{ animationDelay: f.delay }}
        >
          <f.icon className="size-4 text-violet-300" />
          {f.label}
        </motion.div>
      ))}

      <motion.div style={{ opacity }} className="relative z-10 mx-auto max-w-5xl px-5 pt-28 pb-20 text-center">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.15 }}
          className="mx-auto mb-8 inline-flex items-center gap-2 rounded-full glass px-4 py-1.5 text-sm text-white/75"
        >
          <span className="relative flex size-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex size-2 rounded-full bg-emerald-400" />
          </span>
          متاح لمشاريع جديدة الآن
        </motion.div>

        <h1 className="font-display text-5xl font-black leading-[1.15] tracking-tight sm:text-6xl md:text-7xl lg:text-[5.4rem]">
          {words.map((w, i) => (
            <span key={i} className="inline-block overflow-hidden pb-2 align-bottom">
              <motion.span
                className={`inline-block ${i >= 3 ? "text-gradient" : ""}`}
                initial={{ y: "110%", rotate: 6 }}
                animate={{ y: 0, rotate: 0 }}
                transition={{ duration: 0.9, delay: 0.25 + i * 0.09, ease: [0.22, 1, 0.36, 1] }}
              >
                {w}
                {i < words.length - 1 ? "\u00A0" : ""}
              </motion.span>
            </span>
          ))}
        </h1>

        <motion.p
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 0.9 }}
          className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-white/60 md:text-xl"
        >
          مشاريع تخرج متكاملة، هويات بصرية تُبهِر، برامج مخصصة لعملك،
          وصفحات هبوط تحوّل الزائر إلى عميل — كل ذلك بجودة تنافس الاستوديوهات العالمية.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 1.1 }}
          className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row"
        >
          <MagneticButton className="group relative overflow-hidden rounded-full bg-gradient-to-l from-violet-600 to-fuchsia-600 px-9 py-4 text-base font-bold text-white shadow-2xl shadow-violet-600/40">
            <span className="absolute inset-0 -translate-x-full bg-gradient-to-l from-transparent via-white/25 to-transparent transition-transform duration-700 group-hover:translate-x-full" />
            <a href="#work" className="relative">شاهد الأعمال</a>
          </MagneticButton>
          <MagneticButton className="rounded-full glass px-9 py-4 text-base font-bold text-white transition-colors hover:bg-white/10">
            <a href="#contact">اطلب استشارة مجانية</a>
          </MagneticButton>
        </motion.div>
      </motion.div>

      {/* scroll cue */}
      <motion.a
        href="#services"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 2 }}
        className="absolute bottom-8 left-1/2 z-10 -translate-x-1/2 text-white/40"
        aria-label="مرر للأسفل"
      >
        <motion.div animate={{ y: [0, 8, 0] }} transition={{ repeat: Infinity, duration: 1.8 }}>
          <ArrowDown className="size-5" />
        </motion.div>
      </motion.a>
    </section>
  );
}
