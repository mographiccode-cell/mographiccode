import { useEffect } from "react";
import Lenis from "lenis";
import { motion, useMotionValue, useSpring } from "framer-motion";
import Navbar from "@/sections/Navbar";
import Hero from "@/sections/Hero";
import Marquee from "@/sections/Marquee";
import Services from "@/sections/Services";
import Portfolio from "@/sections/Portfolio";
import Process from "@/sections/Process";
import Stats from "@/sections/Stats";
import Testimonials from "@/sections/Testimonials";
import CTA from "@/sections/CTA";
import Footer from "@/sections/Footer";

function CursorGlow() {
  const x = useMotionValue(-400);
  const y = useMotionValue(-400);
  const sx = useSpring(x, { stiffness: 120, damping: 18 });
  const sy = useSpring(y, { stiffness: 120, damping: 18 });

  useEffect(() => {
    const move = (e: PointerEvent) => {
      x.set(e.clientX - 160);
      y.set(e.clientY - 160);
    };
    window.addEventListener("pointermove", move);
    return () => window.removeEventListener("pointermove", move);
  }, [x, y]);

  return (
    <motion.div
      style={{ x: sx, y: sy }}
      className="pointer-events-none fixed left-0 top-0 z-40 hidden size-80 rounded-full bg-violet-500/10 blur-[80px] md:block"
    />
  );
}

export default function App() {
  useEffect(() => {
    const lenis = new Lenis({ lerp: 0.09, smoothWheel: true });
    let raf: number;
    const loop = (time: number) => {
      lenis.raf(time);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);

    // anchor navigation through lenis
    const onClick = (e: Event) => {
      const target = (e.target as HTMLElement).closest('a[href^="#"]');
      if (!target) return;
      const id = target.getAttribute("href");
      if (id && id.length > 1) {
        e.preventDefault();
        lenis.scrollTo(id, { offset: -70, duration: 1.4 });
      }
    };
    document.addEventListener("click", onClick);

    return () => {
      cancelAnimationFrame(raf);
      document.removeEventListener("click", onClick);
      lenis.destroy();
    };
  }, []);

  return (
    <div className="grain relative min-h-screen bg-[#06060a] text-white">
      <CursorGlow />
      <Navbar />
      <main>
        <Hero />
        <Marquee />
        <Services />
        <Portfolio />
        <Stats />
        <Process />
        <Testimonials />
        <CTA />
      </main>
      <Footer />
    </div>
  );
}
