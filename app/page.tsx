"use client";

import { useEffect, useMemo, useState } from "react";

type Permissions = { registrar_cubicaciones?:boolean; revisar_cubicaciones?:boolean; libramiento_cubicaciones?:boolean; pagar_cubicaciones?:boolean; ver_resumen?:boolean; ver_proyectos?:boolean; ver_proyectos_tecnicos?:boolean; ver_cubicaciones?:boolean; ver_calendario?:boolean; ver_reportes?:boolean };
type AppUser = { id: string; username: string; full_name: string; area: string; role: string; permissions?:Permissions; must_change_password?:boolean };
type ManagedUser = AppUser & { active: boolean; created_at: string; last_login_at: string | null };
type TechnicalProject = { id:string; budget_account:string; procurement_process:string; project_year:number; supplier_contractor:string; snip_code:string; has_lot:boolean; lot_number:string; work_name:string; fixed_assets:string; municipality:string; district:string; sector:string; population:number; linear_meters:number|null; budgeted_amount:number; appropriation_amount:number; awarded_amount:number; advance_20_amount:number; fixed_asset_paid_amount:number; measurement_count:number; measurement_status:string; total_measured:number; total_paid:number; work_status:string; work_progress:number; created_at:string };
type AuditEntry={action:string;from_status:string|null;to_status:string;comments:string;created_at:string;user_name:string};
type Measurement={id:string;project_id:string;measurement_number:number;code:string;amount:number;progress_increment:number;description:string;status:"Registrada"|"Revisada"|"Libramiento"|"Pagada";work_name:string;snip_code:string;sector:string;municipality:string;registered_by_name:string;created_at:string;audit:AuditEntry[]};

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

function TechnicalProjectModal({ project, onClose, onSubmit }: { project: TechnicalProject | null; onClose: () => void; onSubmit: (e: React.FormEvent<HTMLFormElement>) => void }) {
  return <div className="modal-backdrop technical-backdrop" onMouseDown={onClose}><form key={project?.id || "new"} className="modal technical-modal" onSubmit={onSubmit} onMouseDown={e=>e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">DIRECCIÓN TÉCNICA</span><h2>{project ? "Editar proyecto" : "Registrar proyecto institucional"}</h2></div><button type="button" onClick={onClose}>×</button></div>
    <div className="form-section"><h3>1. Identificación y contratación</h3><div className="technical-form-grid"><label className="span-2">Obra<input name="work_name" required defaultValue={project?.work_name}/></label><label>Cuenta presupuestaria<input name="budget_account" required defaultValue={project?.budget_account}/></label><label>Proceso de compra o contratación<input name="procurement_process" required defaultValue={project?.procurement_process}/></label><label>Año de realización<input name="project_year" type="number" min="2000" max="2100" required defaultValue={project?.project_year || new Date().getFullYear()}/></label><label>Proveedor o contratista<input name="supplier_contractor" required defaultValue={project?.supplier_contractor}/></label><label>Código SNIP<input name="snip_code" defaultValue={project?.snip_code}/></label><label>No. de lote<input name="lot_number" defaultValue={project?.lot_number}/></label><label className="check-label"><input name="has_lot" type="checkbox" defaultChecked={project?.has_lot}/> El proyecto posee lote</label><label>Activos fijos<input name="fixed_assets" defaultValue={project?.fixed_assets}/></label></div></div>
    <div className="form-section"><h3>2. Ubicación e impacto</h3><div className="technical-form-grid"><label>Municipio<input name="municipality" required defaultValue={project?.municipality}/></label><label>Distrito<input name="district" defaultValue={project?.district}/></label><label>Sector<input name="sector" defaultValue={project?.sector}/></label><label>Población beneficiada<input name="population" type="number" min="0" defaultValue={project?.population || 0}/></label><label>Metros lineales (cuando aplique)<input name="linear_meters" type="number" min="0" step="0.01" defaultValue={project?.linear_meters || ""}/></label></div></div>
    <div className="form-section"><h3>3. Gestión financiera</h3><div className="technical-form-grid"><label>Monto presupuestado<input name="budgeted_amount" type="number" min="0" step="0.01" defaultValue={project?.budgeted_amount || 0}/></label><label>Monto en apropiación<input name="appropriation_amount" type="number" min="0" step="0.01" defaultValue={project?.appropriation_amount || 0}/></label><label>Monto adjudicado<input name="awarded_amount" type="number" min="0" step="0.01" defaultValue={project?.awarded_amount || 0}/></label><label>Avance del 20% pagado<input name="advance_20_amount" type="number" min="0" step="0.01" defaultValue={project?.advance_20_amount || 0}/></label><label>Pago de activos fijos<input name="fixed_asset_paid_amount" type="number" min="0" step="0.01" defaultValue={project?.fixed_asset_paid_amount || 0}/></label></div></div>
    <div className="form-section"><h3>4. Cubicaciones y ejecución</h3><div className="technical-form-grid"><label>Cantidad de cubicaciones<input name="measurement_count" type="number" min="0" defaultValue={project?.measurement_count || 0}/></label><label>Estatus de cubicaciones<select name="measurement_status" defaultValue={project?.measurement_status || "Pendiente"}>{["Pendiente","En revisión","Aprobada","Observada","Pagada"].map(x=><option key={x}>{x}</option>)}</select></label><label>Total cubicado<input name="total_measured" type="number" min="0" step="0.01" defaultValue={project?.total_measured || 0}/></label><label>Total pagado (calculado)<input name="total_paid" type="number" readOnly value={project?.total_paid || 0}/></label><label>Estatus de obra<select name="work_status" defaultValue={project?.work_status || "Planificación"}>{["Planificación","En contratación","Adjudicada","En ejecución","Pausada","Finalizada","Cancelada"].map(x=><option key={x}>{x}</option>)}</select></label><label>Avance de obra (%)<input name="work_progress" type="number" min="0" max="100" step="0.01" defaultValue={project?.work_progress || 0}/></label></div></div>
    <div className="modal-actions"><button type="button" className="outline" onClick={onClose}>Cancelar</button><button className="primary">Guardar proyecto</button></div></form></div>;
}

function MeasurementModal({ projects,onClose,onSubmit }:{projects:TechnicalProject[];onClose:()=>void;onSubmit:(e:React.FormEvent<HTMLFormElement>)=>void}){
  const [selected,setSelected]=useState(projects[0]?.id||""); const project=projects.find(item=>item.id===selected);
  return <div className="modal-backdrop" onMouseDown={onClose}><form className="modal measurement-modal" onSubmit={onSubmit} onMouseDown={e=>e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">NUEVA CUBICACIÓN</span><h2>Registrar etapa de cubicación</h2></div><button type="button" onClick={onClose}>×</button></div><label>Seleccionar código, obra y ubicación<select name="projectId" required value={selected} onChange={e=>setSelected(e.target.value)}><option value="">Seleccione una obra</option>{projects.map(item=><option value={item.id} key={item.id}>{item.snip_code||"Sin SNIP"} · {item.work_name} · {[item.municipality,item.district,item.sector].filter(Boolean).join(" / ")||"Sin ubicación"}</option>)}</select></label>{project&&<div className="project-context"><div><span>CÓDIGO SNIP</span><strong>{project.snip_code||"No especificado"}</strong></div><div><span>OBRA</span><strong>{project.work_name}</strong></div><div><span>MUNICIPIO</span><strong>{project.municipality||"No especificado"}</strong></div><div><span>DISTRITO</span><strong>{project.district||"No especificado"}</strong></div><div><span>SECTOR</span><strong>{project.sector||"No especificado"}</strong></div></div>}<div className="form-row"><label>Monto de la cubicación<input name="amount" required type="number" min="0.01" step="0.01"/></label><label>Incremento de avance (%)<input name="progress" required type="number" min="0" max="100" step="0.01"/></label></div><label>Descripción de los trabajos<textarea name="description" required rows={3}/></label><div className="workflow-notice">El registro no afectará los totales de la obra hasta alcanzar el estatus <b>Pagada</b>.</div><div className="modal-actions"><button type="button" className="outline" onClick={onClose}>Cancelar</button><button className="primary">Registrar cubicación</button></div></form></div>;
}

function AuditModal({measurement,onClose}:{measurement:Measurement;onClose:()=>void}){return <div className="modal-backdrop" onMouseDown={onClose}><div className="modal audit-modal" onMouseDown={e=>e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">AUDITORÍA DE CUBICACIÓN</span><h2>{measurement.code}</h2><p>{measurement.work_name}</p></div><button onClick={onClose}>×</button></div><div className="audit-list">{measurement.audit.map((entry,index)=><div className="audit-entry" key={`${entry.created_at}-${index}`}><i/><div><strong>{entry.to_status}</strong><span>{entry.action} por {entry.user_name}</span><small>{new Date(entry.created_at).toLocaleString("es-DO",{dateStyle:"medium",timeStyle:"short"})}{entry.comments?` · ${entry.comments}`:""}</small></div></div>)}</div><div className="modal-actions"><button className="primary" onClick={onClose}>Cerrar</button></div></div></div>}

export default function Home() {
  const [currentUser, setCurrentUser] = useState<AppUser | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState("");
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);
  const [usersMessage, setUsersMessage] = useState("");
  const [showCreateUser,setShowCreateUser]=useState(false);
  const [technicalProjects, setTechnicalProjects] = useState<TechnicalProject[]>([]);
  const [technicalLoading, setTechnicalLoading] = useState(false);
  const [technicalMessage, setTechnicalMessage] = useState("");
  const [showTechnicalForm, setShowTechnicalForm] = useState(false);
  const [editingTechnical, setEditingTechnical] = useState<TechnicalProject | null>(null);
  const [measurements,setMeasurements]=useState<Measurement[]>([]);
  const [measurementsLoading,setMeasurementsLoading]=useState(false);
  const [measurementMessage,setMeasurementMessage]=useState("");
  const [showMeasurementForm,setShowMeasurementForm]=useState(false);
  const [auditMeasurement,setAuditMeasurement]=useState<Measurement|null>(null);
  const [section, setSection] = useState("Resumen");
  const [filter, setFilter] = useState<Area>("Todos");
  const [query, setQuery] = useState("");
  const [projects, setProjects] = useState<Project[]>(initialProjects);
  const [showForm, setShowForm] = useState(false);
  const [notice, setNotice] = useState(3);

  useEffect(() => {
    fetch("/api/auth/session", { cache: "no-store" })
      .then(response => response.ok ? response.json() : null)
      .then(data => setCurrentUser(data?.user || null))
      .finally(() => setAuthReady(true));
  }, []);

  useEffect(() => {
    if (section !== "Usuarios" || currentUser?.role !== "Administrador") return;
    setUsersLoading(true);
    fetch("/api/users", { cache: "no-store" })
      .then(response => response.json())
      .then(data => setUsers(data.users || []))
      .finally(() => setUsersLoading(false));
  }, [section, currentUser?.role]);

  useEffect(() => {
    if (section === "Proyectos Técnicos" || section === "Cubicaciones") loadTechnicalProjects();
    if (section === "Cubicaciones") loadMeasurements();
  }, [section]);

  useEffect(()=>{if(!currentUser||currentUser.role==="Administrador")return;const views:Array<[string,keyof Permissions]>=[["Resumen","ver_resumen"],["Proyectos","ver_proyectos"],["Proyectos Técnicos","ver_proyectos_tecnicos"],["Cubicaciones","ver_cubicaciones"],["Calendario","ver_calendario"],["Reportes","ver_reportes"]];const allowed=views.filter(([,key])=>Boolean(currentUser.permissions?.[key])).map(([name])=>name);if(!allowed.includes(section))setSection(allowed[0]||"Acceso restringido");},[currentUser,section]);

  async function loadTechnicalProjects() {
    setTechnicalLoading(true);
    const response = await fetch("/api/projects/technical", { cache: "no-store" });
    const data = await response.json();
    setTechnicalProjects(data.projects || []);
    setTechnicalLoading(false);
  }

  async function loadMeasurements(){setMeasurementsLoading(true);const response=await fetch("/api/cubicaciones",{cache:"no-store"});const data=await response.json();setMeasurements(data.measurements||[]);setMeasurementsLoading(false);}

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

  async function handleAuth(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setAuthBusy(true);
    setAuthError("");
    const fd = new FormData(e.currentTarget);
    const username = String(fd.get("username") || "").trim();
    const password = String(fd.get("password") || "");
    if (!username || username.length < 3) {
      setAuthError("El usuario debe tener al menos 3 caracteres.");
      setAuthBusy(false);
      return;
    }
    if (password.length < 6) {
      setAuthError("La contraseña debe tener al menos 6 caracteres.");
      setAuthBusy(false);
      return;
    }
    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    const result = await response.json();
    if (!response.ok) setAuthError(result.error || "No fue posible completar la solicitud.");
    else setCurrentUser(result.user);
    setAuthBusy(false);
  }

  async function logout() {
    await fetch("/api/auth/logout", { method: "POST" });
    setCurrentUser(null);
  }

  async function updateUser(user: ManagedUser, changes: Partial<ManagedUser>) {
    setUsersMessage("");
    const updated = { ...user, ...changes };
    const response = await fetch("/api/users", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: updated.id, role: updated.role, area: updated.area, active: updated.active }) });
    const result = await response.json();
    if (!response.ok) setUsersMessage(result.error || "No se pudo actualizar el usuario.");
    else { setUsers(previous => previous.map(item => item.id === updated.id ? updated : item)); setUsersMessage("Cambios guardados correctamente."); }
  }

  async function updatePermissions(user:ManagedUser,key:keyof Permissions,enabled:boolean){const permissions={...(user.permissions||{}),[key]:enabled};const response=await fetch("/api/users",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:user.id,permissions})});const result=await response.json();if(!response.ok)setUsersMessage(result.error||"No se pudieron actualizar los permisos.");else{setUsers(items=>items.map(item=>item.id===user.id?{...item,permissions}:item));setUsersMessage("Permisos guardados correctamente.");}}

  async function createManagedUser(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setUsersMessage("");const fd=new FormData(e.currentTarget);const viewKeys=["ver_resumen","ver_proyectos","ver_proyectos_tecnicos","ver_cubicaciones","ver_calendario","ver_reportes"];const permissions=Object.fromEntries(viewKeys.map(key=>[key,fd.get(key)==="on"]));const response=await fetch("/api/users",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:String(fd.get("username")),password:String(fd.get("password")),fullName:String(fd.get("fullName")),area:String(fd.get("area")),role:String(fd.get("role")),permissions})});const result=await response.json();if(!response.ok){setUsersMessage(result.error||"No fue posible crear el usuario.");return;}setShowCreateUser(false);setUsers(items=>[...items,result.user]);setUsersMessage("Usuario creado con contraseña temporal.");}

  async function changeFirstPassword(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setAuthBusy(true);setAuthError("");const fd=new FormData(e.currentTarget);const password=String(fd.get("password")||"");const confirmation=String(fd.get("confirmation")||"");if(password.length<8){setAuthError("La nueva contraseña debe tener al menos 8 caracteres.");setAuthBusy(false);return;}if(password!==confirmation){setAuthError("Las contraseñas no coinciden.");setAuthBusy(false);return;}const response=await fetch("/api/auth/change-password",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({password})});const result=await response.json();if(!response.ok)setAuthError(result.error||"No fue posible cambiar la contraseña.");else setCurrentUser(result.user);setAuthBusy(false);}

  function canView(key:keyof Permissions){return currentUser?.role==="Administrador"||Boolean(currentUser?.permissions?.[key]);}

  async function createMeasurement(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setMeasurementMessage("");const fd=new FormData(e.currentTarget);const response=await fetch("/api/cubicaciones",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({projectId:fd.get("projectId"),amount:Number(fd.get("amount")),progress:Number(fd.get("progress")),description:String(fd.get("description"))})});const result=await response.json();if(!response.ok){setMeasurementMessage(result.error||"No se pudo registrar la cubicación.");return;}setShowMeasurementForm(false);setMeasurementMessage(`Cubicación ${result.code} registrada correctamente.`);await loadMeasurements();await loadTechnicalProjects();}

  async function advanceMeasurement(measurement:Measurement){const next=measurement.status==="Registrada"?"Revisada":measurement.status==="Revisada"?"Libramiento":measurement.status==="Libramiento"?"Pagada":null;if(!next)return;const comments=window.prompt(`Comentario para avanzar a ${next}:`)||"";const response=await fetch("/api/cubicaciones",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:measurement.id,status:next,comments})});const result=await response.json();if(!response.ok)setMeasurementMessage(result.error||"No se pudo avanzar la cubicación.");else{setMeasurementMessage(`Cubicación avanzada a ${next}.`);await loadMeasurements();await loadTechnicalProjects();}}
  function canAdvanceMeasurement(status:Measurement["status"]){if(currentUser?.role==="Administrador")return status!=="Pagada";const key=status==="Registrada"?"revisar_cubicaciones":status==="Revisada"?"libramiento_cubicaciones":status==="Libramiento"?"pagar_cubicaciones":null;return key?Boolean(currentUser?.permissions?.[key as keyof Permissions]):false;}

  async function saveTechnicalProject(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); setTechnicalMessage("");
    const fd = new FormData(e.currentTarget);
    const numeric = ["project_year","population","linear_meters","budgeted_amount","appropriation_amount","awarded_amount","advance_20_amount","fixed_asset_paid_amount","measurement_count","total_measured","total_paid","work_progress"];
    const data: Record<string, string | number | boolean | null> = {};
    fd.forEach((value,key) => { data[key] = numeric.includes(key) ? (String(value)==="" ? null : Number(value)) : String(value); });
    data.has_lot = fd.get("has_lot") === "on";
    if (editingTechnical) data.id = editingTechnical.id;
    const response = await fetch("/api/projects/technical", { method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(data) });
    const result = await response.json();
    if (!response.ok) { setTechnicalMessage(result.error || "No fue posible guardar el proyecto."); return; }
    setShowTechnicalForm(false); setEditingTechnical(null); setTechnicalMessage("Proyecto guardado correctamente."); await loadTechnicalProjects();
  }

  if (!authReady) return <div className="auth-loading"><div className="brand-mark">C</div><span>Preparando acceso seguro…</span></div>;

  if(currentUser?.must_change_password)return <main className="login-page"><section className="login-visual"><div className="login-brand"><div className="brand-mark">C</div><div><strong>CORAAMOCA</strong><span>Gestión Institucional</span></div></div><div className="login-message"><span>PRIMER ACCESO</span><h1>Protege tu cuenta.</h1><p>La contraseña temporal debe ser reemplazada antes de entrar al sistema.</p></div></section><section className="login-panel"><form className="login-card" onSubmit={changeFirstPassword}><span className="eyebrow">CAMBIO OBLIGATORIO</span><h2>Crear nueva contraseña</h2><p>Utiliza al menos 8 caracteres y no compartas tu contraseña.</p><label>Nueva contraseña<input name="password" type="password" minLength={8} required autoComplete="new-password"/></label><label>Confirmar contraseña<input name="confirmation" type="password" minLength={8} required autoComplete="new-password"/></label>{authError&&<div className="auth-error">{authError}</div>}<button className="primary login-submit" disabled={authBusy}>{authBusy?"Guardando…":"Cambiar contraseña y continuar"}</button></form></section></main>;

  if (!currentUser) return (
    <main className="login-page">
      <section className="login-visual">
        <div className="login-brand"><div className="brand-mark">C</div><div><strong>CORAAMOCA</strong><span>Gestión Institucional</span></div></div>
        <div className="login-message"><span>PLATAFORMA INSTITUCIONAL</span><h1>Gestionamos hoy<br />el agua del mañana.</h1><p>Un espacio único para coordinar proyectos, recursos y resultados de todas las áreas.</p></div>
        <div className="login-stat"><strong>5</strong><span>áreas integradas</span><strong>100%</strong><span>gestión centralizada</span></div>
      </section>
      <section className="login-panel">
        <form className="login-card" onSubmit={handleAuth}>
          <div className="login-mobile-brand"><div className="brand-mark">C</div><strong>CORAAMOCA</strong></div>
          <span className="eyebrow">ACCESO SEGURO</span>
          <h2>Bienvenido de nuevo</h2>
          <p>Ingresa tus credenciales institucionales.</p>
          <label>Nombre de usuario<input name="username" required minLength={3} autoCapitalize="none" autoComplete="username" placeholder="Ej. jperez" /></label>
          <label>Contraseña<input name="password" required minLength={6} type="password" autoComplete="current-password" placeholder="Mínimo 6 caracteres" /></label>
          {authError && <div className="auth-error">{authError}</div>}
          <button className="primary login-submit" disabled={authBusy}>{authBusy ? "Procesando…" : "Iniciar sesión"}</button>
          <small className="secure-note">▣ Tu sesión está protegida y cifrada por Supabase.</small>
        </form>
      </section>
    </main>
  );

  const userName = currentUser.full_name || currentUser.username || "Usuario";
  const userInitials = String(userName).split(" ").map((part: string) => part[0]).join("").slice(0, 2).toUpperCase();

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand"><div className="brand-mark">C</div><div><strong>CORAAMOCA</strong><span>Gestión Institucional</span></div></div>
        <nav>
          <p className="nav-label">ESPACIO DE TRABAJO</p>
          {[{name:"Resumen",key:"ver_resumen",icon:"▦"},{name:"Proyectos",key:"ver_proyectos",icon:"▤"},{name:"Proyectos Técnicos",key:"ver_proyectos_tecnicos",icon:"⌁"},{name:"Cubicaciones",key:"ver_cubicaciones",icon:"▧"},{name:"Calendario",key:"ver_calendario",icon:"□"},{name:"Reportes",key:"ver_reportes",icon:"▥"}].filter(item=>canView(item.key as keyof Permissions)).map(item => <button key={item.name} className={section === item.name ? "active" : ""} onClick={() => setSection(item.name)}><span>{item.icon}</span>{item.name}</button>)}
          {currentUser.role === "Administrador" && <button className={section === "Usuarios" ? "active" : ""} onClick={() => setSection("Usuarios")}><span>♙</span>Usuarios y roles</button>}
          <p className="nav-label">ÁREAS DE GESTIÓN</p>
          {areaData.map(a => <button key={a.name} onClick={() => { setSection("Proyectos"); setFilter(a.name as Area); }}><i className={`dot ${a.color}`} />{a.name}</button>)}
        </nav>
        <div className="sidebar-foot"><div className="avatar">{userInitials}</div><div><strong>{userName}</strong><span>{currentUser.role || "Usuario"}</span></div><button title="Cerrar sesión" onClick={logout}>↪</button></div>
      </aside>

      <main>
        <header>
          <div className="mobile-brand">CORAAMOCA</div>
          <label className="search"><span>⌕</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Buscar proyectos, responsables..." /><kbd>⌘ K</kbd></label>
          <div className="header-actions"><button className="icon-btn" onClick={() => setNotice(0)}>♧{notice > 0 && <b>{notice}</b>}</button><button className="primary" onClick={() => section === "Cubicaciones" ? setShowMeasurementForm(true) : section === "Proyectos Técnicos" ? (setEditingTechnical(null),setShowTechnicalForm(true)) : setShowForm(true)}>＋ {section === "Cubicaciones" ? "Nueva cubicación" : "Nuevo proyecto"}</button></div>
        </header>

        <div className="content">
          <div className="page-head"><div><span className="eyebrow">CENTRO DE OPERACIONES</span><h1>{section === "Resumen" ? "Resumen institucional" : section}</h1><p>Seguimiento integral de metas, recursos y resultados · Julio 2026</p></div><button className="outline" onClick={() => window.print()}>⇩ Exportar reporte</button></div>

          {section === "Usuarios" && <section className="users-panel">
            <div className="users-summary"><div><span>USUARIOS REGISTRADOS</span><strong>{users.length}</strong></div><div><span>CUENTAS ACTIVAS</span><strong>{users.filter(user => user.active).length}</strong></div><div><span>ADMINISTRADORES</span><strong>{users.filter(user => user.role === "Administrador").length}</strong></div></div>
            <div className="users-card"><div className="users-card-head"><div><h2>Administración de usuarios</h2><p>Crea cuentas, asigna roles y define las vistas disponibles.</p></div><button className="primary" onClick={()=>setShowCreateUser(true)}>＋ Crear usuario</button></div>
              {usersMessage && <div className={usersMessage.startsWith("Cambios")||usersMessage.startsWith("Usuario creado")||usersMessage.startsWith("Permisos") ? "users-success" : "auth-error"}>{usersMessage}</div>}
              {usersLoading ? <div className="users-empty">Cargando usuarios…</div> : <div className="users-table-wrap"><table className="users-table permissions-table"><thead><tr><th>USUARIO</th><th>ÁREA</th><th>ROL</th><th>ESTADO</th><th>PERMISOS</th><th>ÚLTIMO ACCESO</th></tr></thead><tbody>{users.map(user => <tr key={user.id}><td><div className="user-identity"><div className="avatar">{user.full_name.split(" ").map(part => part[0]).join("").slice(0,2)}</div><div><strong>{user.full_name}</strong><span>@{user.username}{user.must_change_password?" · Contraseña temporal":""}</span></div></div></td><td><select value={user.area} onChange={event => updateUser(user,{ area:event.target.value })}>{areaData.map(area => <option key={area.name}>{area.name}</option>)}</select></td><td><select value={user.role} onChange={event => updateUser(user,{ role:event.target.value })}>{["Administrador","Director","Supervisor","Analista","Consulta","Usuario"].map(role => <option key={role}>{role}</option>)}</select></td><td><button className={`user-status ${user.active ? "is-active" : "is-inactive"}`} onClick={() => updateUser(user,{ active:!user.active })}>{user.active ? "● Activo" : "● Inactivo"}</button></td><td><div className="permission-toggles">{[["ver_resumen","Resumen"],["ver_proyectos","Proyectos"],["ver_proyectos_tecnicos","P. Técnicos"],["ver_cubicaciones","Cubicaciones"],["ver_calendario","Calendario"],["ver_reportes","Reportes"],["registrar_cubicaciones","Registrar cub."],["revisar_cubicaciones","Revisar cub."],["libramiento_cubicaciones","Libramiento"],["pagar_cubicaciones","Pagar cub."]].map(([key,label])=><label key={key}><input type="checkbox" checked={Boolean(user.role==="Administrador"||user.permissions?.[key as keyof Permissions])} disabled={user.role==="Administrador"} onChange={e=>updatePermissions(user,key as keyof Permissions,e.target.checked)}/>{label}</label>)}</div></td><td>{user.last_login_at ? new Date(user.last_login_at).toLocaleString("es-DO",{dateStyle:"medium",timeStyle:"short"}) : "Sin acceso"}</td></tr>)}</tbody></table></div>}
            </div>
          </section>}
          {section==="Acceso restringido"&&<section className="technical-empty"><strong>Sin vistas asignadas</strong><span>Solicita al administrador que habilite los módulos correspondientes a tu función.</span></section>}

          {section === "Proyectos Técnicos" && <section className="technical-panel">
            <div className="direction-strip"><strong>Dirección líder</strong><span>Dirección Técnica</span><i>＋</i><strong>Direcciones participantes</strong><span>Administrativa y Financiera</span><span>Planificación y Desarrollo</span></div>
            <div className="technical-kpis"><article><span>PROYECTOS</span><strong>{technicalProjects.length}</strong></article><article><span>MONTO PRESUPUESTADO</span><strong>{money(technicalProjects.reduce((sum,p)=>sum+Number(p.budgeted_amount),0))}</strong></article><article><span>TOTAL CUBICADO</span><strong>{money(technicalProjects.reduce((sum,p)=>sum+Number(p.total_measured),0))}</strong></article><article><span>TOTAL PAGADO</span><strong>{money(technicalProjects.reduce((sum,p)=>sum+Number(p.total_paid),0))}</strong></article></div>
            {technicalMessage && <div className={technicalMessage.startsWith("Proyecto guardado") ? "users-success" : "auth-error"}>{technicalMessage}</div>}
            <div className="technical-card"><div className="users-card-head"><div><h2>Cartera de obras y proyectos técnicos</h2><p>Control presupuestario, contractual, territorial y de ejecución.</p></div><button className="primary" onClick={()=>{setEditingTechnical(null);setShowTechnicalForm(true)}}>＋ Registrar proyecto</button></div>
              {technicalLoading ? <div className="users-empty">Cargando proyectos…</div> : technicalProjects.length===0 ? <div className="technical-empty"><strong>No hay proyectos técnicos registrados</strong><span>Registra la primera obra para iniciar el seguimiento interdireccional.</span></div> : <div className="users-table-wrap"><table className="technical-table"><thead><tr><th>OBRA / SNIP</th><th>UBICACIÓN</th><th>CONTRATISTA</th><th>PRESUPUESTO</th><th>CUBICADO / PAGADO</th><th>AVANCE</th><th>ESTATUS</th><th></th></tr></thead><tbody>{technicalProjects.map(project=><tr key={project.id}><td><strong>{project.work_name}</strong><small>{project.snip_code || "Sin código SNIP"} · {project.project_year}</small></td><td><b>{project.municipality}</b><small>{[project.district,project.sector].filter(Boolean).join(" · ")}</small></td><td>{project.supplier_contractor}</td><td><b>{money(Number(project.budgeted_amount))}</b><small>Adjudicado: {money(Number(project.awarded_amount))}</small></td><td><b>{money(Number(project.total_measured))}</b><small>Pagado: {money(Number(project.total_paid))}</small></td><td><div className="tech-progress"><i><em style={{width:`${project.work_progress}%`}} /></i><b>{project.work_progress}%</b></div></td><td><span className="work-status">{project.work_status}</span><small>{project.measurement_status}</small></td><td><button className="row-action" onClick={()=>{setEditingTechnical(project);setShowTechnicalForm(true)}}>Editar</button></td></tr>)}</tbody></table></div>}
            </div>
          </section>}

          {section === "Cubicaciones" && <section className="measurements-panel">
            <div className="workflow-head"><div><span>FLUJO DE APROBACIÓN</span><h2>Cubicaciones de obras</h2><p>Cada cubicación avanza por la línea de mando antes de afectar la ejecución financiera y física.</p></div><button className="primary" onClick={()=>setShowMeasurementForm(true)} disabled={!technicalProjects.length}>＋ Registrar cubicación</button></div>
            <div className="workflow-line">{["Registrada","Revisada","Libramiento","Pagada"].map((stage,index)=><div key={stage}><i>{index+1}</i><strong>{stage}</strong><span>{index===0?"Sin afectación":index===1?"Validación técnica":index===2?"Trámite financiero":"Impacta obra"}</span></div>)}</div>
            <div className="measurement-kpis"><article><span>REGISTRADAS</span><strong>{measurements.filter(x=>x.status==="Registrada").length}</strong></article><article><span>EN REVISIÓN / LIBRAMIENTO</span><strong>{measurements.filter(x=>x.status==="Revisada"||x.status==="Libramiento").length}</strong></article><article><span>PAGADAS</span><strong>{measurements.filter(x=>x.status==="Pagada").length}</strong></article><article><span>MONTO PAGADO</span><strong>{money(measurements.filter(x=>x.status==="Pagada").reduce((s,x)=>s+Number(x.amount),0))}</strong></article></div>
            {measurementMessage&&<div className={measurementMessage.includes("correctamente")||measurementMessage.includes("avanzada")?"users-success":"auth-error"}>{measurementMessage}</div>}
            <div className="technical-card"><div className="users-card-head"><div><h2>Expedientes de cubicación</h2><p>Etapas, responsables y trazabilidad completa.</p></div></div>{measurementsLoading?<div className="users-empty">Cargando cubicaciones…</div>:measurements.length===0?<div className="technical-empty"><strong>No hay cubicaciones registradas</strong><span>Seleccione una obra y registre su primera etapa de cubicación.</span></div>:<div className="users-table-wrap"><table className="measurement-table"><thead><tr><th>CÓDIGO / ETAPA</th><th>OBRA Y SECTOR</th><th>MONTO</th><th>AVANCE</th><th>REGISTRADO POR</th><th>ESTATUS</th><th>ACCIONES</th></tr></thead><tbody>{measurements.map(item=><tr key={item.id}><td><strong>{item.code}</strong><small>Cubicación No. {item.measurement_number}</small></td><td><b>{item.work_name}</b><small>{item.snip_code||"Sin SNIP"} · {item.sector||item.municipality}</small></td><td><b>{money(Number(item.amount))}</b><small>{item.status==="Pagada"?"Aplicado a la obra":"Sin afectar presupuesto"}</small></td><td><b>＋{item.progress_increment}%</b><small>{item.status==="Pagada"?"Avance aplicado":"Pendiente de pago"}</small></td><td>{item.registered_by_name}<small>{new Date(item.created_at).toLocaleDateString("es-DO")}</small></td><td><span className={`measurement-status status-${item.status.toLowerCase()}`}>{item.status}</span></td><td><div className="measurement-actions"><button className="row-action" onClick={()=>setAuditMeasurement(item)}>Auditoría</button>{canAdvanceMeasurement(item.status)&&<button className="advance-action" onClick={()=>advanceMeasurement(item)}>Avanzar →</button>}</div></td></tr>)}</tbody></table></div>}</div>
          </section>}

          <div className={section === "Usuarios" || section === "Proyectos Técnicos" || section === "Cubicaciones" || section === "Acceso restringido" ? "section-hidden" : ""}>

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
        </div>
      </main>

      {showForm && <div className="modal-backdrop" onMouseDown={() => setShowForm(false)}><form className="modal" onSubmit={addProject} onMouseDown={e => e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">NUEVA INICIATIVA</span><h2>Registrar proyecto</h2></div><button type="button" onClick={() => setShowForm(false)}>×</button></div><label>Nombre del proyecto<input name="name" required placeholder="Ej. Ampliación de cobertura rural" /></label><div className="form-row"><label>Área<select name="area">{areaData.map(a => <option key={a.name}>{a.name}</option>)}</select></label><label>Responsable<input name="owner" required placeholder="Nombre o unidad" /></label></div><div className="form-row"><label>Presupuesto (RD$)<input name="budget" required type="number" min="0" placeholder="0" /></label><label>Fecha de entrega<input name="due" required type="date" /></label></div><div className="modal-actions"><button type="button" className="outline" onClick={() => setShowForm(false)}>Cancelar</button><button className="primary">Crear proyecto</button></div></form></div>}
      {showCreateUser&&<div className="modal-backdrop" onMouseDown={()=>setShowCreateUser(false)}><form className="modal technical-modal" onSubmit={createManagedUser} onMouseDown={e=>e.stopPropagation()}><div className="modal-head"><div><span className="eyebrow">ADMINISTRACIÓN</span><h2>Crear usuario institucional</h2><p>La contraseña será temporal y deberá cambiarse en el primer acceso.</p></div><button type="button" onClick={()=>setShowCreateUser(false)}>×</button></div><div className="technical-form-grid"><label>Nombre completo<input name="fullName" required minLength={3}/></label><label>Nombre de usuario<input name="username" required minLength={3} autoCapitalize="none"/></label><label>Contraseña temporal<input name="password" required minLength={8} type="password"/></label><label>Área<select name="area">{areaData.map(a=><option key={a.name}>{a.name}</option>)}</select></label><label>Rol<select name="role">{["Usuario","Consulta","Analista","Supervisor","Director","Administrador"].map(role=><option key={role}>{role}</option>)}</select></label></div><div className="form-section"><h3>Permisos de vista iniciales</h3><div className="permission-toggles create-permissions">{[["ver_resumen","Resumen"],["ver_proyectos","Proyectos"],["ver_proyectos_tecnicos","Proyectos Técnicos"],["ver_cubicaciones","Cubicaciones"],["ver_calendario","Calendario"],["ver_reportes","Reportes"]].map(([key,label])=><label key={key}><input name={key} type="checkbox" defaultChecked/>{label}</label>)}</div></div><div className="modal-actions"><button type="button" className="outline" onClick={()=>setShowCreateUser(false)}>Cancelar</button><button className="primary">Crear usuario</button></div></form></div>}
      {showTechnicalForm && <TechnicalProjectModal project={editingTechnical} onClose={()=>setShowTechnicalForm(false)} onSubmit={saveTechnicalProject} />}
      {showMeasurementForm && <MeasurementModal projects={technicalProjects} onClose={()=>setShowMeasurementForm(false)} onSubmit={createMeasurement}/>} 
      {auditMeasurement && <AuditModal measurement={auditMeasurement} onClose={()=>setAuditMeasurement(null)}/>} 
    </div>
  );
}
