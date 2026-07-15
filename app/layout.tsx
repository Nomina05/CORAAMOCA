import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CORAAMOCA | Gestión Institucional",
  description: "Plataforma integral de seguimiento de proyectos y gestión institucional.",
  icons: { icon: "/favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es"><body>{children}</body></html>;
}
