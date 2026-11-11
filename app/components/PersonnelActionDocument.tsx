import type {CSSProperties} from "react";

export type OfficialPersonnelAction={
 id:string;action_number:number;employee_code:string;document_number:string;full_name:string;
 action_type:string;effective_date:string;other_action:string;present_state:Record<string,unknown>;
 proposed_state:Record<string,unknown>;observations:string;recommendation:string;
 immediate_supervisor:string;department_manager:string;payroll_officer:string;general_director:string;
 approval_dates:Record<string,string>;
};

const stateKeys=['direction','department','division','section','position','salary'] as const;
const optionPosition:Record<string,[number,number]>={
 APERTURA_CONCURSO:[0,0],AUMENTO_SUELDO:[0,1],ASCENSO:[0,2],INTERINAJE:[0,3],VACACIONES:[0,4],LICENCIA_ESTUDIOS:[0,5],LICENCIA_SIN_SUELDO:[0,6],
 LICENCIA_ENFERMEDAD:[1,0],LICENCIA_EMBARAZO:[1,1],COMPENSACION:[1,2],REINGRESO_TRABAJO:[1,3],NOMBRAMIENTO_REGULAR:[1,4],NOMBRAMIENTO_CONTRATO:[1,5],RESCISION_CONTRATO:[1,6],
 PRORROGA_CONTRATO:[2,0],DESPIDO:[2,1],ABANDONO_TRABAJO:[2,2],RENUNCIA:[2,3],TRASLADO:[2,4],OTROS:[2,5],SUPLENCIA:[2,5]
};
const proposedStateActions=new Set(['AUMENTO_SUELDO','ASCENSO','INTERINAJE','SUPLENCIA','TRASLADO']);
const money=(value:unknown)=>Number(value||0).toLocaleString('es-DO',{minimumFractionDigits:2,maximumFractionDigits:2});
const idNumber=(value:unknown)=>{const digits=String(value||'').replace(/\D/g,'');return digits.length===11?`${digits.slice(0,3)}-${digits.slice(3,10)}-${digits.slice(10)}`:String(value||'')};
const date=(value:unknown)=>{const raw=String(value||'');if(!raw)return '';const parts=raw.slice(0,10).split('-');return parts.length===3?`${parts[2]}/${parts[1]}/${parts[0]}`:raw};
const value=(data:Record<string,unknown>,key:string)=>key==='salary'&&data[key]!==''&&data[key]!=null?money(data[key]):String(data[key]||'');
const fittedFontSize=(content:string,key:string)=>{if(key==='salary')return 12;if(content.length<=20)return 13.5;if(content.length<=28)return 12.5;if(content.length<=36)return 11.5;if(content.length<=46)return 10.5;if(content.length<=58)return 9.5;return 8.5};

export default function PersonnelActionDocument({item,className='' }:{item:OfficialPersonnelAction;className?:string}){
 const dates=item.approval_dates||{},present=item.present_state||{},proposed=proposedStateActions.has(item.action_type)?item.proposed_state||{}:{},position=optionPosition[item.action_type];
 const checkStyle=position?({'--oad-col':position[0],'--oad-row':position[1]} as CSSProperties):undefined;
 return <article className={`official-action-document ${className}`} aria-label={`Acción de personal ${item.action_number}`}>
  <span className="oad-data oad-name">{item.full_name}</span><span className="oad-data oad-code">{item.employee_code}</span>
  <span className="oad-data oad-id">{idNumber(item.document_number)}</span><span className="oad-data oad-effective">{date(item.effective_date)}</span>
  {stateKeys.map((key,index)=>{const content=value(present,key);return <span key={`present-${key}`} className="oad-data oad-state oad-present" style={{top:`${238+index*33}px`,fontSize:`${fittedFontSize(content,key)}px`}}>{content}</span>})}
  {stateKeys.map((key,index)=>{const content=value(proposed,key);return <span key={`proposed-${key}`} className="oad-data oad-state oad-proposed" style={{top:`${238+index*33}px`,fontSize:`${fittedFontSize(content,key)}px`}}>{content}</span>})}
  {position&&<span className="oad-selected-check" style={checkStyle}>✓</span>}{(item.action_type==='OTROS'||item.action_type==='SUPLENCIA')&&<span className="oad-data oad-other">{item.action_type==='SUPLENCIA'?'SUPLENCIA':item.other_action||''}</span>}
  <span className="oad-data oad-observation-text">{item.observations||''}</span><span className="oad-data oad-recommendation-text">{item.recommendation||''}</span>
  <i className="oad-clean oad-clean-payroll-date"/><i className="oad-clean oad-clean-payroll-name"/><i className="oad-clean oad-clean-director-date"/><i className="oad-clean oad-clean-director-name"/>
  <span className="oad-data oad-sign oad-recommendation-date">{date(dates.recommendation_date)}</span><span className="oad-data oad-sign oad-supervisor">{item.immediate_supervisor||''}</span>
  <span className="oad-data oad-sign oad-department-date">{date(dates.department_date)}</span><span className="oad-data oad-sign oad-department-manager">{item.department_manager||''}</span>
  <span className="oad-data oad-sign oad-payroll-date">{date(dates.payroll_date)}</span><span className="oad-data oad-sign oad-payroll-officer">{item.payroll_officer||''}</span>
  <span className="oad-data oad-sign oad-director-date">{date(dates.director_date)}</span><span className="oad-data oad-sign oad-general-director">{item.general_director||''}</span>
 </article>
}
