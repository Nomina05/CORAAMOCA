"use client";

import {useEffect,useMemo,useRef,useState} from "react";
import type {LatLngExpression,Map as LeafletMap} from "leaflet";

type CustomerPoint={id:string;account_code:string;full_name:string;customer_category:string;sector:string;latitude:number|null;longitude:number|null};
type MeterPoint={id:string;meter_number:string;customer_name:string;status:string;last_reading:number|null;latitude:number|null;longitude:number|null};

export default function CommercialGeoMap({customers,meters}:{customers:CustomerPoint[];meters:MeterPoint[]}){
 const container=useRef<HTMLDivElement>(null);
 const mapRef=useRef<LeafletMap|null>(null);
 const [showCustomers,setShowCustomers]=useState(true);
 const [showMeters,setShowMeters]=useState(true);
 const customerPoints=useMemo(()=>customers.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[customers]);
 const meterPoints=useMemo(()=>meters.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[meters]);

 useEffect(()=>{
  let active=true;
  void import("leaflet").then(L=>{
   if(!active||!container.current)return;
   mapRef.current?.remove();
   const map=L.map(container.current,{zoomControl:true,attributionControl:true});
   mapRef.current=map;
   L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);
   const coordinates:LatLngExpression[]=[];
   if(showCustomers)customerPoints.forEach(item=>{
    const position:LatLngExpression=[Number(item.latitude),Number(item.longitude)];coordinates.push(position);
    L.marker(position,{icon:L.divIcon({className:"commercial-map-marker",html:'<span class="customer-marker">U</span>',iconSize:[28,28],iconAnchor:[14,14]})}).addTo(map).bindPopup(`<strong>${escapeHtml(item.full_name)}</strong><br>No. contrato: ${escapeHtml(item.account_code)}<br>Categoría: ${escapeHtml(item.customer_category||"Sin categoría")}<br>Sector: ${escapeHtml(item.sector||"Sin sector")}`);
   });
   if(showMeters)meterPoints.forEach(item=>{
    const position:LatLngExpression=[Number(item.latitude),Number(item.longitude)];coordinates.push(position);
    L.marker(position,{icon:L.divIcon({className:"commercial-map-marker",html:'<span class="meter-marker">M</span>',iconSize:[26,26],iconAnchor:[13,13]})}).addTo(map).bindPopup(`<strong>Medidor ${escapeHtml(item.meter_number)}</strong><br>Usuario: ${escapeHtml(item.customer_name)}<br>Estado: ${escapeHtml(item.status)}<br>Última lectura: ${item.last_reading??"Sin lectura"}`);
   });
   if(coordinates.length)map.fitBounds(L.latLngBounds(coordinates).pad(.18),{maxZoom:15});
   else map.fitBounds([[19.20,-70.90],[19.78,-70.25]]);
  });
  return()=>{active=false;mapRef.current?.remove();mapRef.current=null};
 },[customerPoints,meterPoints,showCustomers,showMeters]);

 return <section className="commercial-map-card"><header><div><span>MAPA GEOREFERENCIAL · PROVINCIA ESPAILLAT</span><h3>Usuarios y medidores instalados</h3><p>Los puntos se incorporan automáticamente al registrar coordenadas válidas.</p></div><div className="commercial-map-filters"><label><input type="checkbox" checked={showCustomers} onChange={event=>setShowCustomers(event.target.checked)}/> Usuarios <i className="customer-dot"/></label><label><input type="checkbox" checked={showMeters} onChange={event=>setShowMeters(event.target.checked)}/> Medidores <i className="meter-dot"/></label></div></header><div ref={container} className="commercial-map"/><footer><span><strong>{customerPoints.length}</strong> usuarios georreferenciados</span><span><strong>{meterPoints.length}</strong> medidores georreferenciados</span><span><strong>{customers.length-customerPoints.length+meters.length-meterPoints.length}</strong> registros pendientes de coordenadas</span></footer></section>;
}

function escapeHtml(value:string){return String(value??"").replace(/[&<>'"]/g,character=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"})[character]||character)}
