import Image from "next/image";

export type OfficialPersonnelAction={
 id:string;action_number:number;employee_code:string;document_number:string;full_name:string;
 action_type:string;effective_date:string;other_action:string;present_state:Record<string,unknown>;
 proposed_state:Record<string,unknown>;observations:string;recommendation:string;
 immediate_supervisor:string;department_manager:string;payroll_officer:string;general_director:string;
 approval_dates:Record<string,string>;
};

const fields=[['direction','Dirección'],['department','Departamento'],['division','División'],['section','Sección'],['position','Cargo'],['salary','Sueldo RD$']] as const;
const actionOptions=[['APERTURA_CONCURSO','APERTURA DE CONCURSO'],['LICENCIA_ENFERMEDAD','LICENCIA POR ENFERMEDAD'],['PRORROGA_CONTRATO','PRÓRROGA DE CONTRATO'],['AUMENTO_SUELDO','AUMENTO DE SUELDO'],['LICENCIA_EMBARAZO','LICENCIA POR EMBARAZO'],['DESPIDO','DESPIDO'],['ASCENSO','ASCENSO'],['COMPENSACION','COMPENSACIÓN'],['ABANDONO_TRABAJO','ABANDONO DEL TRABAJO'],['INTERINAJE','INTERINAJE'],['REINGRESO_TRABAJO','REINGRESO AL TRABAJO'],['RENUNCIA','RENUNCIA'],['VACACIONES','VACACIONES'],['NOMBRAMIENTO_REGULAR','NOMBRAMIENTO REGULAR'],['TRASLADO','TRASLADO'],['LICENCIA_ESTUDIOS','LICENCIA POR ESTUDIOS'],['NOMBRAMIENTO_CONTRATO','NOMBRAMIENTO POR CONTRATO'],['OTROS','OTROS'],['LICENCIA_SIN_SUELDO','LICENCIA SIN SUELDO'],['RESCISION_CONTRATO','RESCISIÓN DE CONTRATO']] as const;
const money=(value:unknown)=>Number(value||0).toLocaleString('es-DO',{minimumFractionDigits:2,maximumFractionDigits:2});
const idNumber=(value:unknown)=>{const digits=String(value||'').replace(/\D/g,'');return digits.length===11?`${digits.slice(0,3)}-${digits.slice(3,10)}-${digits.slice(10)}`:String(value||'')};
const date=(value:unknown)=>{const raw=String(value||'');if(!raw)return '';const parts=raw.slice(0,10).split('-');return parts.length===3?`${parts[2]}/${parts[1]}/${parts[0]}`:raw};

function StateColumn({title,data}:{title:string;data:Record<string,unknown>}){
 return <section className="oad-state-column"><h3>{title}</h3>{fields.map(([key,label])=><div className="oad-line" key={key}><span>{label}</span><b>{key==='salary'&&data[key]!==''&&data[key]!=null?money(data[key]):String(data[key]||'')}</b></div>)}</section>
}

function Signature({value,label}:{value:string;label:string}){return <div className="oad-signature"><b>{value}</b><span>{label}</span></div>}

export default function PersonnelActionDocument({item,className='' }:{item:OfficialPersonnelAction;className?:string}){
 const dates=item.approval_dates||{};
 return <article className={`official-action-document ${className}`}>
  <header className="oad-header"><div className="oad-logo"><Image src="/logo-coraamoca-oficial.jpg" alt="CORAAMOCA" width={500} height={388} quality={90}/></div><div className="oad-heading"><h1>CORPORACIÓN DEL ACUEDUCTO Y ALCANTARILLADO DE MOCA</h1><strong>(CORAAMOCA)</strong><h2>ACCIÓN DE PERSONAL</h2></div></header>
  <section className="oad-identification"><div><span>Nombre:</span><b>{item.full_name}</b></div><div><span>Codif. No.:</span><b>{item.employee_code}</b></div><div><span>Cédula No.:</span><b>{idNumber(item.document_number)}</b></div><div><span>Efectivo a partir de:</span><b>{date(item.effective_date)}</b></div></section>
  <section className="oad-states"><StateColumn title="ESTADO PRESENTE" data={item.present_state||{}}/><StateColumn title="ESTADO QUE SE PROPONE" data={item.proposed_state||{}}/></section>
  <h3 className="oad-action-title">A C C I Ó N</h3>
  <section className="oad-options">{actionOptions.map(([key,label])=><div key={key}><i>{item.action_type===key?'✓':''}</i><span>{label}</span>{key==='OTROS'&&<b>{item.other_action||''}</b>}</div>)}</section>
  <section className="oad-observations"><span>Observaciones:</span><p>{item.observations||''}</p></section>
  <section className="oad-approvals"><div><h4>Recomendación</h4><p>{item.recommendation||''}</p><div className="oad-signature-grid"><Signature value={date(dates.recommendation_date)} label="Fecha"/><Signature value={item.immediate_supervisor||''} label="Superior Inmediato"/><Signature value={date(dates.department_date)} label="Fecha"/><Signature value={item.department_manager||''} label="Enc. Departamento"/></div></div><div><h4>Visto Bueno</h4><p></p><div className="oad-signature-grid"><Signature value={date(dates.payroll_date)} label="Fecha"/><Signature value={item.payroll_officer||''} label="Enc. Registro Control y Nómina"/><Signature value={date(dates.director_date)} label="Fecha"/><Signature value={item.general_director||''} label="Director General"/></div></div></section>
 </article>
}
