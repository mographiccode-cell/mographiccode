import { useState } from "react";
import TiltCard from "@/components/effects/TiltCard";
import Reveal from "@/components/effects/Reveal";
import { ArrowUpLeft, Play, X, ExternalLink } from "lucide-react";

type Work = {
  title: string;
  titleEn: string;
  category: string;
  year: string;
  image: string;
  accent: string;
  url: string;
  big?: boolean;
};

const works: Work[] = [
  {
    title: "SESAM — مخبز فاخر",
    titleEn: "SESAM Artisan Bakery",
    category: "صفحة هبوط — مطاعم وضيافة",
    year: "2025",
    image: "/mographiccode/projects/sesam.jpg",
    accent: "bg-amber-400",
    url: "https://mographiccode-cell.github.io/sesam-sa-landing/",
    big: true,
  },
  {
    title: "JUN — جمال عُمان",
    titleEn: "JUN Beauty of Oman",
    category: "صفحة هبوط — جمال و Yaşam",
    year: "2025",
    image: "/mographiccode/projects/jun.jpg",
    accent: "bg-rose-400",
    url: "https://mographiccode-cell.github.io/jun-omn-landing/",
  },
  {
    title: "HEED — مقهى مختص",
    titleEn: "HEED Specialty Coffee",
    category: "صفحة هبوط — مقاهي وضيافة",
    year: "2025",
    image: "/mographiccode/projects/heed.jpg",
    accent: "bg-emerald-400",
    url: "https://mographiccode-cell.github.io/heed-cafe-landing/",
  },
  {
    title: "Uniq Piece — فن يدوي",
    titleEn: "Uniq Piece Handcrafted Mugs",
    category: "صفحة هبوط — منتجات فنية",
    year: "2024",
    image: "/mographiccode/projects/uniqpi.jpg",
    accent: "bg-violet-400",
    url: "https://mographiccode-cell.github.io/uniq-pi/",
  },
  {
    title: "MyCard — دعوات رقمية",
    titleEn: "MyCard Oman Digital Invitations",
    category: "صفحة هبوط — خدمات رقمية",
    year: "2024",
    image: "/mographiccode/projects/mycard.jpg",
    accent: "bg-cyan-400",
    url: "https://mographiccode-cell.github.io/mycard-oman-landing/",
    big: true,
  },
  {
    title: "AVA Studio — إنتاج إبداعي",
    titleEn: "AVA Studio Qatar",
    category: "صفحة هبوط — استوديو إبداعي",
    year: "2024",
    image: "/mographiccode/projects/avastudio.jpg",
    accent: "bg-slate-400",
    url: "https://mographiccode-cell.github.io/avastudio.qa/",
  },
];

function DemoModal({ work, onClose }: { work: Work; onClose: () => void }) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="relative mx-4 flex h-[85vh] w-full max-w-6xl flex-col overflow-hidden rounded-3xl border border-white/10 bg-[#0a0a0f]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* header */}
        <div className="flex items-center justify-between border-b border-white/10 px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1.5">
              <span className="size-3 rounded-full bg-red-400/80" />
              <span className="size-3 rounded-full bg-amber-400/80" />
              <span className="size-3 rounded-full bg-emerald-400/80" />
            </div>
            <div className="rounded-full bg-white/5 px-4 py-1.5 text-sm text-white/60">
              {work.titleEn}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <a
              href={work.url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 rounded-full bg-white/10 px-4 py-2 text-sm text-white transition-colors hover:bg-white/20"
            >
              <ExternalLink className="size-4" />
              فتح في تبويب جديد
            </a>
            <button
              onClick={onClose}
              className="grid size-9 place-items-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
            >
              <X className="size-5" />
            </button>
          </div>
        </div>

        {/* iframe */}
        <div className="relative flex-1">
          <iframe
            src={work.url}
            title={work.titleEn}
            className="h-full w-full border-0"
            loading="lazy"
            sandbox="allow-scripts allow-same-origin allow-popups allow-forms"
          />
        </div>
      </div>
    </div>
  );
}

export default function Portfolio() {
  const [activeDemo, setActiveDemo] = useState<Work | null>(null);

  return (
    <>
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
            <Reveal key={w.titleEn} delay={i * 0.08} className={w.big ? "md:col-span-2" : ""}>
              <TiltCard className="group h-full">
                <div className="relative flex h-full min-h-[320px] flex-col justify-end overflow-hidden rounded-3xl border border-white/8 md:min-h-[360px]">
                  {/* real screenshot */}
                  <img
                    src={w.image}
                    alt={w.titleEn}
                    className="absolute inset-0 h-full w-full object-cover object-top transition-transform duration-700 group-hover:scale-105"
                  />

                  {/* dark overlay for text readability */}
                  <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />

                  {/* hover overlay with play button */}
                  <div className="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition-opacity duration-300 group-hover:opacity-100">
                    <button
                      onClick={() => setActiveDemo(w)}
                      className="flex items-center gap-3 rounded-full bg-white px-6 py-3 font-bold text-black shadow-lg transition-transform hover:scale-105"
                    >
                      <Play className="size-5 fill-current" />
                      تشغيل الديمو
                    </button>
                  </div>

                  {/* bottom info */}
                  <div className="relative z-10 flex items-end justify-between gap-4 p-6">
                    <div>
                      <div className="mb-2 flex items-center gap-2 text-xs text-white/70">
                        <span className={`size-1.5 rounded-full ${w.accent}`} />
                        {w.category} · {w.year}
                      </div>
                      <h3 className="font-display text-2xl font-bold text-white">{w.title}</h3>
                      <p className="mt-1 text-sm text-white/50">{w.titleEn}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => setActiveDemo(w)}
                        className="grid size-11 shrink-0 place-items-center rounded-full border border-white/25 bg-white/10 backdrop-blur transition-all duration-300 hover:bg-white hover:text-black"
                        title="تشغيل الديمو"
                      >
                        <Play className="size-5 fill-current" />
                      </button>
                      <a
                        href={w.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="grid size-11 shrink-0 place-items-center rounded-full border border-white/25 bg-white/10 backdrop-blur transition-all duration-300 hover:bg-white hover:text-black"
                        title="فتح في تبويب جديد"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <ArrowUpLeft className="size-5" />
                      </a>
                    </div>
                  </div>
                </div>
              </TiltCard>
            </Reveal>
          ))}
        </div>
      </section>

      {/* demo modal */}
      {activeDemo && <DemoModal work={activeDemo} onClose={() => setActiveDemo(null)} />}
    </>
  );
}
