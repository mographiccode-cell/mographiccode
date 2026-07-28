import { Sparkles, Instagram, Twitter, Linkedin, Dribbble } from "lucide-react";

const socials = [
  { icon: Instagram, label: "انستغرام" },
  { icon: Twitter, label: "تويتر" },
  { icon: Linkedin, label: "لينكدإن" },
  { icon: Dribbble, label: "دريبل" },
];

export default function Footer() {
  return (
    <footer className="border-t border-white/5 bg-[#050508]">
      <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-8 px-5 py-12 md:flex-row md:px-10">
        <div className="flex items-center gap-2">
          <span className="grid size-9 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500">
            <Sparkles className="size-4.5 text-white" />
          </span>
          <div>
            <p className="font-display text-lg font-bold">نُقطة</p>
            <p className="text-xs text-white/40">حيث تبدأ الفكرة</p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {socials.map((s) => (
            <a
              key={s.label}
              href="#top"
              aria-label={s.label}
              className="grid size-10 place-items-center rounded-full border border-white/10 text-white/50 transition-all duration-300 hover:-translate-y-1 hover:border-violet-400/50 hover:text-white"
            >
              <s.icon className="size-4.5" />
            </a>
          ))}
        </div>

        <p className="text-sm text-white/35">© ٢٠٢٥ نُقطة — جميع الحقوق محفوظة</p>
      </div>
    </footer>
  );
}
