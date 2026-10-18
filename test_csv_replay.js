// Replay the supplied v1.1 diagnostic CSV through the actual v1.2 MQL core.
// This verifies closed-bar state reconstruction, not a replacement for tick testing.
const fs=require('fs'),assert=require('assert');
const {ctx,p}=require('./test_core.js');
const filename=process.argv[2];if(!filename)throw new Error('Pass a v1.1 CSV path');
function parseCSV(text){
 const rows=[];let row=[],field='',quote=false;
 for(let i=0;i<text.length;i++){
  let c=text[i];
  if(c==='"'){if(quote&&text[i+1]==='"'){field+='"';i++;}else quote=!quote;}
  else if(c===','&&!quote){row.push(field);field='';}
  else if(c==='\n'&&!quote){row.push(field.replace(/\r$/,''));rows.push(row);row=[];field='';}
  else field+=c;
 }
 if(field||row.length){row.push(field.replace(/\r$/,''));rows.push(row);}
 const head=rows.shift();head[0]=head[0].replace(/^\uFEFF/,'');
 return rows.map(row=>Object.fromEntries(head.map((h,i)=>[h,row[i]])));
}
const rows=parseCSV(fs.readFileSync(filename,'utf8'));
const bars=rows.filter(r=>r.event==='HISTORY_BAR'||r.event==='CLOSED_BAR');
const live=new Map(rows.filter(r=>r.event==='LIVE_SIGNAL').map(r=>[r.bar_time,r]));
let state={};ctx.FRReset(state);let approx=0,retained=0;
const regressionDates=['2026.08.17 18:00:00','2026.09.22 05:00:00'];
for(let i=0;i<bars.length;i++){
 const r=bars[i],n=k=>Number(r[k]),dir=v=>v==='BUY'?1:v==='SELL'?-1:0;
 const b={index:i,cross:dir(r.cross_event),breakout:dir(r.breakout_event),rangeValid:r.range_valid==='1',
  fast:n('fast_ma'),slow:n('slow_ma'),fastPast:n('fast_ma')-n('fast_delta'),slowPast:n('slow_ma')-n('slow_delta'),
  atr:n('atr_used'),low:n('low'),high:n('high'),close:n('close')};
 const event=live.get(r.bar_time);
 if(event){
  assert.equal(bars[state.crossBar]?.bar_time,event.active_cross_time,'Live cross generation must match');
  state.consumed=true;retained++;
 }
 const signal=ctx.FRCommit(state,b,p,r.event==='HISTORY_BAR');
 if(r.event==='CLOSED_BAR') assert.equal(signal,0,'No synthetic runtime touch');
 else if(signal)approx++;
 if(regressionDates.includes(r.bar_time)){
  assert.equal(state.consumed,false,'Unobserved touch must not consume cross');
  console.log('PASS regression '+r.bar_time+': no arrow, not consumed');
 }
}
assert.equal(retained,9);assert.equal(approx,15);
console.log('PASS CSV replay: '+bars.length+' bars, '+retained+' observed signals retained; '+approx+' pre-start historical estimates.');
