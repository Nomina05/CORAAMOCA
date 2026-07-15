"use client";

import { useEffect, useMemo, useState } from "react";

type Area = "Todos" | "Institucional" | "Gestión Humana" | "Financiera" | "Técnica" | "Comercial";
type Project = { id: number; code: string; name: string; area: Exclude<Area, "Todos">; owner: string; progress: number; budget: number; spent: number; status: "En curso" | "En riesgo" | "Completado"; due: string };

const initialProjects: Project[] = [
  { id: 1, code: "PI-026", name: "Plan estratégico institucional 2026", area: "Institucional", owner: "Dirección Ejecutiva", progress: 72, budget: 3800000, spent: 2460000, status: "En curso", due: "30 Sep" },
  { id: 2, code: "GH-014", name: "Evaluación de desempeño y competencias", area: "Gestión Humana", owner: "Laura Méndez", progress: 58, budget: 1250000, spent: 710000, status: "En curso", due: "18 Ago" },
  { id: 3, code: "GF-031", name: "Automatización presupuestaria", area: "Financiera", owner: "Carlos Peralta", progress: 43, budget: 5600000, spent: 3190000, status: "En riesgo", due: "12 Ago" },
  { id: 4, code: "GT-019", name: "Rehabilitación red de distribución norte", area: "Técnica", owner: "Ing. Mariel Soto", progress: 81, budget: 18400000, spent: 14230000, status: "En curso", due: "05 Oct" },
  { id: 5, code: "GC-022", name: "Actualización del catastro de usuarios", area: "Comercial", owner: "Samuel Peña", progress: 66, budget: 7900000, spent: 4810000, status: "En curso", due: "22 Sep" },
  { id: 6, code: "GT-011", name: "Optimización estación de bombeo central", area: "Técnica", owner: "José Rosario", progress: 100, budget: 9200000, spent: 8940000, status: "Completado", due: "Completado" },
];

const areaData = [
  { name: "Institucional", icon: "⌂", color: "blue", metric: "12", label: "iniciativas activas", progress: 74 },
  { name: "Gestión Humana", icon: "♙", color: "violet", metric: "428", label: "colaboradores", progress: 68 },
  { name: "Financiera", icon: "$", color: "amber", metric: "84.6%", label: "ejecución presupuestaria", progress: 85 },
  { name: "Técnica", icon: "⌁", color: "cyan", metric: "19", label: "proyectos en campo", progress: 71 },
  { name: "Comercial", icon: "↗", color: "green", metric: "92.3%", label: "recaudación mensual", progress: 92 },
];

const money = (value: number) => new Intl.NumberFormat("es-DO", { style: "currency", currency: "DOP", maximumFractionDigits: 0 }).format(value);

export default function Home() {
  const [section, setSection] = useState("Resumen");
  const [filter, setFilter] = useState<Area>("Todos");
  const [query, setQuery] = useState("");
  const [projects, setProjects] = useState<Project[]>(initialProjects);
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState(3);

  useEffect(() => {
    const saved = window.localStorage.getItem("coraamoca-projects");
    if (saved) {
      try { setProjects(JSON.parse(saved)); } catch { /* keep the institutional sample data */ }
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem("coraamoca-projects", JSON.stringify(projects));
  }, [projects]);

  const filtered = useMemo(() => projects.filter(p => (filter === "Todos" || p.area === filter) && `${p.name} ${p.code} ${p.owner}`.toLowerCase().includes(query.toLowerCase())), [projects, filter, query]);
  const totals = useMemo(() => ({ budget: projects.reduce((a, p) => a + p.budget, 0), spent: projects.reduce((a, p) => a + p.spent, 0), avg: Math.round(projects.reduce((a, p) => a + p.progress, 0) / projects.length) }), [projects]);

  function addProject(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const area = fd.get("area") as Project["area"];
    setProjects(prev => [{ id: Date.now(), code: `${area.slice(0, 2).toUpperCase()}-${String(prev.length + 1).padStart(3, "0")}`, name: String(fd.get("name")), area, owner: String(fd.get("owner")), progress: 0, budget: Number(fd.get("budget")), spent: 0, status: "En curso", due: String(fd.get("due")) }, ...prev]);
    setShowForm(false);
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand"><div className="brand-mark">C</div><div><strong>CORAAMOCA</strong><span>Gestión Institucional</span></div></div>
        <nav>
          <p className="nav-label">ESPACIO DE TRABAJO</p>
          {["Resumen", "Proyectos", "Calendario", "Reportes"].map((x, i) => <button key={x} className={section === x ? "active" : ""} onClick={() => setSection(x)}><span>{["▦", "▤", "□", "▥"][i]}</span>{x}</button>)}
          <p className="nav-label">ÁREAS DE GESTIÓN</p>
          {areaData.map(a => <button key={a.name} onClick={() => { setSection("Proyectos"); setFilter(a.name as Area); }}><i className={`dot ${a.color}`} />{a.name}</button>)}
        </nav>
        <div className="sidebar-foot"><div className="avatar">AM</div><div><strong>Ana Martínez</strong><span>Administradora</span></div><button>•••</button></div>
      </aside>

      <main>
        <header>
          <div className="mobile-brand">CORAAMOCA</div>
          <label className="search"><span>⌕</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Buscar proyectos, responsables..." /><kbd>⌘ K</kbd></label>
          <div className="header-actions"><button className="icon-btn" onClick={() => setNotice(0)}>♧{notice > 0 && <b>{notice}</b>}</button><button className="primary" onClick={() => setShowForm(true)}>＋ Nuevo proyecto</button></div>
        </header>

        <div className="content">
          <div className="page-head"><div><span className="eyebrow">CENTRO DE OPERACIONES</span><h1>{section === "Resumen" ? "Resumen institucional" : section}</h1><p>Seguimiento integral de metas, recursos y resultados · Julio 2026</p></div><button className="outline" onClick={() => window.print()}>⇩ Exportar reporte</button></div>

          <section className="hero-grid">
            <article className="score-card"><div className="score-top"><div><span>ÍNDICE DE DESEMPEÑO</span><strong>78.4</strong><small>/100</small></div><div className="trend">↗ 6.2%</div></div><div className="score-track"><i style={{ width: "78.4%" }} /></div><div className="score-meta"><span>Planificado <b>82%</b></span><span>Ejecutado <b>74%</b></span><span>Eficiencia <b>79%</b></span></div></article>
            <article className="deadline-card"><div className="mini-title"><span>◷</span><div><strong>Próximo hito crítico</strong><small>En 8 días</small></div></div><h3>Cierre presupuestario Q2</h3><p>Consolidación y entrega de ejecución trimestral.</p><div className="deadline-foot"><span>Gestión Financiera</span><b>23 JUL</b></div></article>
          </section>

          <section className="kpis">
            <article><span>Proyectos activos</span><strong>{projects.filter(p => p.status !== "Completado").length}</strong><small className="up">↗ 3 este mes</small></article>
            <article><span>Avance promedio</span><strong>{totals.avg}%</strong><small className="up">↗ 4.1% vs. junio</small></article>
            <article><span>Presupuesto total</span><strong>RD$ {(totals.budget / 1000000).toFixed(1)}M</strong><small>{Math.round(totals.spent / totals.budget * 100)}% ejecutado</small></article>
            <article><span>Requieren atención</span><strong className="danger">{projects.filter(p => p.status === "En riesgo").length}</strong><small className="danger">Revisar hoy</small></article>
          </section>

          <div className="section-title"><div><h2>Desempeño por área</h2><p>Progreso frente a las metas del período</p></div><button onClick={() => { setSection("Proyectos"); setFilter("Todos"); }}>Ver todos los proyectos →</button></div>
          <section className="area-grid">{areaData.map(a => <article key={a.name} onClick={() => { setSection("Proyectos"); setFilter(a.name as Area); }}><div className={`area-icon ${a.color}`}>{a.icon}</div><div className="area-copy"><strong>{a.name}</strong><span>{a.metric}</span><small>{a.label}</small></div><div className="area-progress"><div><span>Progreso</span><b>{a.progress}%</b></div><i><em style={{ width: `${a.progress}%` }} /></i></div></article>)}</section>

          <div className="section-title project-title"><div><h2>Cartera de proyectos</h2><p>Estado de las iniciativas institucionales</p></div><select value={filter} onChange={e => setFilter(e.target.value as Area)}>{["Todos", ...areaData.map(a => a.name)].map(x => <option key={x}>{x}</option>)}</select></div>
          <section className="table-card"><div className="table-wrap"><table><thead><tr><th>PROYECTO</th><th>ÁREA</th><th>RESPONSABLE</th><th>AVANCE</th><th>PRESUPUESTO</th><th>ESTADO</th><th>ENTREGA</th></tr></thead><tbody>{filtered.map(p => <tr key={p.id}><td><b>{p.code}</b><strong>{p.name}</strong></td><td><span className="area-pill">{p.area}</span></td><td>{p.owner}</td><td><div className="progress-cell"><i><em style={{ width: `${p.progress}%` }} /></i></div><b>{p.progress}%</b></td><td><b>{money(p.budget)}</b><small>{Math.round(p.spent / p.budget * 100)}% usado</small></td><td><span className={`status ${p.status.replace(" ", "-").toLowerCase()}`}>● {p.status}</span></td><td>{p.due}</td></tr>)}</tbody></table>{filtered.length === 0 && <div className="empty">No se encontraron proyectos con esos criterios.</div>}</div></section>
        </div>
      </main>

      {showForm && <div className="modal-backdrop" onMouseDown={() => setShowForm(false)}><form className="modal" onSubmit={addProject} onMouseDown={e => e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">NUEVA INICIATIVA</span><h2>Registrar proyecto</h2></div><button type="button" onClick={() => setShowForm(false)}>×</button></div><label>Nombre del proyecto<input name="name" required placeholder="Ej. Ampliación de cobertura rural" /></label><div className="form-row"><label>Área<select name="area">{areaData.map(a => <option key={a.name}>{a.name}</option>)}</select></label><label>Responsable<input name="owner" required placeholder="Nombre o unidad" /></label></div><div className="form-row"><label>Presupuesto (RD$)<input name="budget" required type="number" min="0" placeholder="0" /></label><label>Fecha de entrega<input name="due" required type="date" /></label></div><div className="modal-actions"><button type="button" className="outline" onClick={() => setShowForm(false)}>Cancelar</button><button className="primary">Crear proyecto</button></div></form></div>}
    </div>
  );
}
