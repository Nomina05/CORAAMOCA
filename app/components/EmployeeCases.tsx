"use client";
import {FormEvent,useCallback,useEffect,useMemo,useState} from "react";

type CaseType="PERMISO"|"VACACION"|"AMONESTACION";
type Employee={id:string;employee_code:string;full_name:string;position_name:string;employment_status:string};
type Item={id:string;case_number:number;employee_code:string;full_name:string;position_name:string;direction_name:string;case_type:CaseType;category:string;start_date:string;end_date:string;day_count:number;paid:boolean;severity:string;reason:string;observations:string;status:string;created_by_name:string;approved_by_name?:string};
const configs={
 PERMISO:{title:"Permisos laborales",eyebrow:"CONTROL DE PERMISOS",description:"Solicitudes de ausencia temporal, con o sin disfrute de salario.",categories:["Médico","Diligencia personal","Estudios","Fallecimiento familiar","Matrimonio","Nacimiento de hijo","Otro"]},
 VACACION:{title:"Vacaciones",eyebrow:"PROGRAMACIÓN DE VACACIONES",description:"Planificación, aprobación y seguimiento de los períodos de vacaciones.",categories:["Vacaciones ordinarias","Vacaciones fraccionadas","Vacaciones pendientes"]},
 AMONESTACION:{title:"Amonestaciones",eyebrow:"RÉGIMEN DISCIPLINARIO",description:"Registro y notificación de medidas disciplinarias vinculadas al expediente.",categories:["Incumplimiento de horario","Inasistencia","Incumplimiento de funciones","Conducta inadecuada","Negligencia","Otro"]}
} as const;
const date=(value:string)=>new Date(`${value}T12:00:00`).toLocaleDateString("es-DO");

export default function EmployeeCases({type,canCreate=false,canApprove=false}:{type:CaseType;canCreate?:boolean;canApprove?:boolean}){
 const current=configs[type];
 const [employees,setEmployees]=useState<Employee[]>([]),[items,setItems]=useState<Item[]>([]),[year,setYear]=useState(new Date().getFullYear());
 const [message,setMessage]=useState(""),[busy,setBusy]=useState(false),[query,setQuery]=useState("");
 const load=useCallback(async()=>{setBusy(true);try{const response=await fetch(`/api/hr/employee-cases?type=${type}&year=${year}`,{cache:"no-store"}),data=await response.json();setItems(response.ok&&Array.isArray(data.items)?data.items:[]);setEmployees(response.ok&&Array.isArray(data.employees)?data.employees:[]);if(!response.ok)setMessage(data.error||"No fue posible cargar los registros.")}finally{setBusy(false)}},[type,year]);
 useEffect(()=>{load()},[load]);
 async function save(event:FormEvent<HTMLFormElement>){event.preventDefault();setBusy(true);const form=event.currentTarget,data=Object.fromEntries(new FormData(form));const response=await fetch("/api/hr/employee-cases",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({...data,case_type:type,paid:data.paid==="true"})}),body=await response.json();setMessage(response.ok?"Registro guardado correctamente.":body.error);if(response.ok){form.reset();await load()}else setBusy(false)}
 async function decide(item:Item,decision:"APROBAR"|"RECHAZAR"){const notes=window.prompt(decision==="RECHAZAR"?"Motivo obligatorio del rechazo:":"Observación de la decisión (opcional):","");if(notes===null||(decision==="RECHAZAR"&&!notes.trim()))return;setBusy(true);const response=await fetch("/api/hr/employee-cases",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:item.id,decision,notes})}),body=await response.json();setMessage(response.ok?"Registro actualizado correctamente.":body.error);await load()}
 const filtered=useMemo(()=>items.filter(item=>`${item.full_name} ${item.employee_code} ${item.reason} ${item.direction_name}`.toLowerCase().includes(query.toLowerCase())),[items,query]);
 const pending=items.filter(i=>i.status==="SOLICITADO"||i.status==="REGISTRADA").length;
 const approved=items.filter(i=>i.status==="APROBADO"||i.status==="NOTIFICADA").length;
 const days=items.filter(i=>i.status==="APROBADO").reduce((sum,item)=>sum+item.day_count,0);
 return <section className="employee-registry-panel">
  <div className="direction-strip"><strong>DIRECCIÓN RESPONSABLE</strong><span>Dirección de Recursos Humanos · {current.title}</span></div>
  <div className="employee-registry-head"><div><span className="eyebrow">{current.eyebrow}</span><h2>{current.title}</h2><p>{current.description}</p></div><div><select value={year} onChange={e=>setYear(+e.target.value)}>{Array.from({length:6},(_,i)=>2026+i).map(y=><option key={y}>{y}</option>)}</select></div></div>
  <div className="technical-kpis"><article><span>REGISTROS DEL AÑO</span><strong>{items.length}</strong></article><article><span>PENDIENTES</span><strong>{pending}</strong></article><article><span>{type==="AMONESTACION"?"NOTIFICADAS":"APROBADOS"}</span><strong>{approved}</strong></article><article><span>{type==="AMONESTACION"?"EMPLEADOS RELACIONADOS":"DÍAS APROBADOS"}</span><strong>{type==="AMONESTACION"?new Set(items.map(i=>i.employee_code)).size:days}</strong></article></div>
  {message&&<div className="form-message">{message}</div>}
  {canCreate&&<form className="case-form" onSubmit={save}>
   <label>Colaborador<select name="employee_id" required><option value="">Seleccionar empleado</option>{employees.map(e=><option value={e.id} key={e.id}>{e.employee_code} · {e.full_name} · {e.position_name}</option>)}</select></label>
   <label>Tipo o categoría<select name="category" required><option value="">Seleccionar</option>{current.categories.map(c=><option key={c}>{c}</option>)}</select></label>
   <label>{type==="AMONESTACION"?"Fecha del hecho":"Fecha inicial"}<input name="start_date" type="date" required/></label>
   {type!=="AMONESTACION"&&<label>Fecha final<input name="end_date" type="date" required/></label>}
   {type==="PERMISO"&&<label>Condición<select name="paid" defaultValue="true"><option value="true">Con disfrute de salario</option><option value="false">Sin disfrute de salario</option></select></label>}
   {type==="AMONESTACION"&&<label>Nivel<select name="severity" required><option value="">Seleccionar</option><option>Leve</option><option>Moderada</option><option>Grave</option></select></label>}
   <label className="case-wide">Motivo<input name="reason" required maxLength={500}/></label><label className="case-wide">Observaciones<textarea name="observations" rows={3}/></label><div className="case-wide"><button className="primary" disabled={busy}>{busy?"Guardando…":"Registrar"}</button></div>
  </form>}
  <div className="technical-card"><div className="users-card-head"><div><h2>Historial de {current.title.toLowerCase()}</h2><p>Registro vinculado al expediente maestro y a la auditoría institucional.</p></div><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Buscar empleado, motivo o área"/></div>
   {busy&&!items.length?<div className="users-empty">Cargando registros…</div>:!filtered.length?<div className="technical-empty"><strong>No existen registros para este período</strong><span>Utilice el formulario superior para iniciar el módulo.</span></div>:<div className="users-table-wrap"><table className="employee-registry-table"><thead><tr><th>NO. / COLABORADOR</th><th>TIPO</th><th>PERÍODO</th><th>MOTIVO</th><th>ESTATUS</th><th>RESPONSABLE</th><th>ACCIONES</th></tr></thead><tbody>{filtered.map(item=><tr key={item.id}>
    <td><strong>#{item.case_number} · {item.full_name}</strong><small>{item.employee_code} · {item.position_name}</small></td><td><strong>{item.category}</strong><small>{item.severity||(type==="PERMISO"?(item.paid?"Con salario":"Sin salario"):"")}</small></td><td>{date(item.start_date)}<small>{type!=="AMONESTACION"?`Hasta ${date(item.end_date)} · ${item.day_count} días`:""}</small></td><td>{item.reason}<small>{item.observations}</small></td><td><span className={`user-status ${item.status==="APROBADO"||item.status==="NOTIFICADA"?"is-active":"is-inactive"}`}>{item.status}</span></td><td>{item.created_by_name}<small>{item.approved_by_name?`Procesado por ${item.approved_by_name}`:"Pendiente de decisión"}</small></td><td>{canApprove&&(item.status==="SOLICITADO"||item.status==="REGISTRADA")?<div><button className="row-action" onClick={()=>decide(item,"APROBAR")}>{type==="AMONESTACION"?"Notificar":"Aprobar"}</button> <button className="row-action" onClick={()=>decide(item,"RECHAZAR")}>Rechazar</button></div>:"—"}</td>
   </tr>)}</tbody></table></div>}
  </div>
  <style jsx>{`.case-form{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;padding:18px;border:1px solid #dbe5eb;border-radius:11px;background:#fff}.case-form label{display:grid;gap:6px;color:#536d80;font-size:9px;font-weight:800}.case-form input,.case-form select,.case-form textarea{width:100%;padding:10px;border:1px solid #d7e2e8;border-radius:7px;background:#fff;color:#173c55;font-size:10px}.case-wide{grid-column:1/-1}@media(max-width:800px){.case-form{grid-template-columns:1fr}.case-wide{grid-column:auto}}`}</style>
 </section>
}
