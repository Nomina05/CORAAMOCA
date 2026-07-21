export const permissionGranted=(role,permissions,key)=>role==="Administrador"||permissions?.[key]===true;

export const paidTotal=({fixedAssetPaid=0,advancePaid=0,measurements=[]})=>
  Number(fixedAssetPaid)+Number(advancePaid)+measurements
    .filter(item=>item.status==="Pagada")
    .reduce((total,item)=>total+Number(item.amount||0),0);

export const nextMeasurementStatus=(status,action="ADVANCE")=>{
  if(action==="RETURN")return status==="Revisada"?"Cubicada":status==="Libramiento"?"Revisada":null;
  return status==="Cubicada"?"Revisada":status==="Revisada"?"Libramiento":status==="Libramiento"?"Pagada":null;
};

export const paymentWithinAppropriation=(appropriation,payments)=>Number(payments)<=Number(appropriation);

export const payrollContribution=(gross,rate,cap)=>Math.round(Math.min(Number(gross),Number(cap))*Number(rate)*100)/100;

export const monthlyIsr2026=(gross,employeeTss=0)=>{
  const annual=Math.max((Number(gross)-Number(employeeTss))*12,0);
  const tax=annual<=416220?0:annual<=624329?(annual-416220)*0.15:annual<=867123?31216+(annual-624329)*0.20:79776+(annual-867123)*0.25;
  return Math.round(tax/12*100)/100;
};
