import { useEffect, useState } from "react";
import { motion, useScroll, useSpring, AnimatePresence } from "framer-motion";
import { Menu, X, Sparkles } from "lucide-react";

const links = [
  { href: "#services", label: "الخدمات" },
  { href: "#work", label: "الأعمال" },
  { href: "#process", label: "آلية العمل" },
  { href: "#testimonials", label: "آراء العملاء" },
];

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const { scrollYProgress } = useScroll();
  const progress = useSpring(scrollYProgress, { stiffness: 120, damping: 26 });

  useEffect(() => {
    const fn = () => setScrolled(window.scrollY > 24);
    window.addEventListener("scroll", fn, { passive: true });
    return () => window.removeEventListener("scroll", fn);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50">
      <motion.div
        initial={{ y: -80, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
        className={`mx-auto flex max-w-7xl items-center justify-between px-5 py-4 transition-all duration-500 md:px-10 ${
          scrolled ? "glass mt-3 rounded-2xl md:mx-6 lg:mx-auto" : ""
        }`}
      >
        <a href="#top" className="flex items-center gap-2">
          <span className="grid size-9 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 shadow-lg shadow-violet-500/30">
            <Sparkles className="size-4.5 text-white" />
          </span>
          <span className="font-display text-xl font-bold tracking-tight">نُقطة</span>
        </a>

        <nav className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="relative text-sm font-medium text-white/70 transition-colors hover:text-white after:absolute after:-bottom-1 after:right-0 after:h-px after:w-0 after:bg-gradient-to-l after:from-violet-400 after:to-fuchsia-400 after:transition-all after:duration-300 hover:after:w-full"
            >
              {l.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <a
            href="#contact"
            className="hidden rounded-full bg-white px-5 py-2 text-sm font-bold text-[#06060a] transition-transform duration-300 hover:scale-105 md:block"
          >
            ابدأ مشروعك
          </a>
          <button
            className="grid size-10 place-items-center rounded-xl glass md:hidden"
            onClick={() => setOpen(!open)}
            aria-label="القائمة"
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
      </motion.div>

      <AnimatePresence>
        {open && (
          <motion.nav
            initial={{ opacity: 0, y: -12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            className="glass mx-5 mt-2 flex flex-col gap-1 rounded-2xl p-4 md:hidden"
          >
            {links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                onClick={() => setOpen(false)}
                className="rounded-xl px-4 py-3 text-sm font-medium text-white/80 hover:bg-white/5"
              >
                {l.label}
              </a>
            ))}
            <a
              href="#contact"
              onClick={() => setOpen(false)}
              className="mt-2 rounded-xl bg-white px-4 py-3 text-center text-sm font-bold text-[#06060a]"
            >
              ابدأ مشروعك
            </a>
          </motion.nav>
        )}
      </AnimatePresence>

      {/* scroll progress */}
      <motion.div
        style={{ scaleX: progress }}
        className="absolute bottom-0 right-0 h-[2px] w-full origin-right bg-gradient-to-l from-violet-500 via-fuchsia-500 to-cyan-400"
      />
    </header>
  );
}
