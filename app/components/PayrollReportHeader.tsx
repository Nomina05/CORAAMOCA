type Props={
 title:string; paymentType?:string; processDate?:Date; page?:number;
 program?:string|number; subprogram?:string|number; project?:string|number;
 activity?:string|number; objectCode?:string; showSocialSecurityTitle?:boolean;
};
const pad=(value:string|number|undefined,size=2)=>String(value??0).padStart(size,"0");
export default function PayrollReportHeader({title,paymentType="FIJO",processDate=new Date(),page=1,program=1,subprogram=0,project=0,activity=1,objectCode="",showSocialSecurityTitle=false}:Props){
 const date=processDate.toLocaleDateString("es-DO",{day:"2-digit",month:"2-digit",year:"numeric"});
 return <header className="payroll-institutional-header">
  <div className="payroll-header-top">
   <div className="payroll-header-process"><b>Proc. {date}</b><span>{paymentType}</span><strong>CONCEPTO: {title.toUpperCase()}</strong></div>
   <div className="payroll-header-country"><h1>REPÚBLICA DOMINICANA</h1><span>CORAAMOCA</span></div>
   <div className="payroll-header-page"><b>LIB. ________</b><span>Página&nbsp;&nbsp;&nbsp;{page}</span><div><strong>Capítulo y Prosusa de la Institución Procesada:</strong><small>6107010100010010000001 - CORPORACIÓN DEL ACUEDUCTO Y ALCANTARILLADO DE MOCA</small></div></div>
  </div>
  <div className="payroll-header-codes"><span><b>CAP.</b> 6107</span><span><b>SUB-CAP.</b> 01</span><span><b>DAF.</b> 01</span><span><b>UE.</b> 0001</span><span><b>PROG.</b> {pad(program)}</span><span><b>SUB-PROG.</b> {pad(subprogram)}</span><span><b>PROY.</b> {pad(project)}</span><span><b>ACT.</b> {pad(activity,4)}</span><span className="payroll-header-institution">CORPORACIÓN DEL ACUEDUCTO Y ALCANTARILLADO DE MOCA</span><span><b>FUNCIÓN</b></span><span><b>OBJETO</b> {objectCode||"—"}</span></div>
  {showSocialSecurityTitle&&<div className="payroll-header-tss">Tesorería de la Seguridad Social</div>}
 </header>
}
