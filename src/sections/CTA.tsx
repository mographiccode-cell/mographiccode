import { motion } from "framer-motion";
import Reveal from "@/components/effects/Reveal";
import MagneticButton from "@/components/effects/MagneticButton";
import { MessageCircle, Mail } from "lucide-react";

export default function CTA() {
  return (
    <section id="contact" className="relative mx-auto max-w-7xl px-5 pb-28 md:px-10">
      <Reveal>
        <div className="relative overflow-hidden rounded-[2.5rem] border border-white/10 bg-gradient-to-br from-violet-950/60 via-[#0d0a18] to-fuchsia-950/50 px-6 py-20 text-center md:px-16 md:py-28">
          {/* orbiting ring */}
          <div className="pointer-events-none absolute -top-40 left-1/2 -translate-x-1/2">
            <div className="animate-spin-slow size-[560px] rounded-full border border-dashed border-violet-400/20" />
          </div>
          <div className="pointer-events-none absolute -bottom-52 left-1/2 -translate-x-1/2">
            <div className="animate-spin-slow size-[680px] rounded-full border border-dashed border-fuchsia-400/15" style={{ animationDirection: "reverse" }} />
          </div>
          <div className="animate-pulse-glow absolute top-0 left-1/2 size-[400px] -translate-x-1/2 rounded-full bg-violet-600/20 blur-[130px]" />

          <motion.p
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            className="relative mb-4 text-sm font-bold tracking-widest text-violet-300"
          >
            — جاهز نبدأ؟
          </motion.p>
          <h2 className="font-display relative mx-auto max-w-3xl text-4xl font-black leading-tight md:text-6xl">
            عندك فكرة؟
            <br />
            <span className="text-gradient">خلّنا نحوّلها لواقع.</span>
          </h2>
          <p className="relative mx-auto mt-6 max-w-xl text-lg text-white/55">
            احجز استشارتك المجانية اليوم — نرد خلال أقل من ٢٤ ساعة، والأسعار تناسب الطلاب وأصحاب الأعمال.
          </p>

          <div className="relative mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
            <MagneticButton className="group flex items-center gap-2.5 rounded-full bg-gradient-to-l from-violet-600 to-fuchsia-600 px-9 py-4 text-base font-bold text-white shadow-2xl shadow-fuchsia-600/30">
              <MessageCircle className="size-5 transition-transform group-hover:rotate-12" />
              تواصل واتساب
            </MagneticButton>
            <MagneticButton className="flex items-center gap-2.5 rounded-full glass px-9 py-4 text-base font-bold transition-colors hover:bg-white/10">
              <Mail className="size-5" />
              أرسل بريدًا
            </MagneticButton>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
