// Executes the actual MQL core after syntax-only translation to JavaScript.
const fs=require('fs'),assert=require('assert'),vm=require('vm');
let source=fs.readFileSync(__dirname+'/FirstReturnCore.mqh','utf8');
source=source.replace(/struct\s+\w+\s*\{[\s\S]*?\};/g,'')
 .replace(/\b(void|bool|int)\s+(FR\w+)\(([^)]*)\)/g,(_,t,n,args)=>
  'function '+n+'('+args.replace(/\b(FRState|FRBar|FRParams)\s*&\s*/g,'').replace(/\bbool\s+/g,'')+')')
 .replace(/\bdouble\s+(\w+)/g,'let $1')
 .replace(/MathAbs/g,'Math.abs').replace(/MathMax/g,'Math.max');
const ctx={Math};vm.createContext(ctx);vm.runInContext(source,ctx);
const p={pairBars:10,expiryBars:30,slopeATR:.05,touchATR:.1,departureATR:.5};
function state(){const s={};ctx.FRReset(s);return s;}
function bar(i,changes={}){return {index:i,cross:0,breakout:0,rangeValid:false,
 fast:100,slow:102,fastPast:101,slowPast:103,atr:10,low:93,high:94,close:94,...changes};}
function step(s,i,c={}){return ctx.FRStep(s,bar(i,c),p);}
function armed(){let s=state();step(s,0,{cross:-1,breakout:-1,rangeValid:true});step(s,1);return s;}
let checks=0;function check(name,f){f();checks++;console.log('PASS '+name);}
check('breakout and cross candle cannot signal',()=>{let s=state();assert.equal(step(s,0,{cross:-1,breakout:-1,rangeValid:true,high:100}),0);assert.equal(s.departed,false);});
check('first sell return consumes cross',()=>{let s=armed();assert.equal(step(s,2,{high:99.5,low:98}),-1);assert.equal(step(s,3,{high:100}),0);});
check('no prior departure: no touch signal',()=>{let s=state();step(s,0,{cross:-1,breakout:-1,rangeValid:true});assert.equal(step(s,1,{low:99,high:101,close:99}),0);});
check('flat slow MA rejected',()=>{let s=armed();assert.equal(step(s,2,{slowPast:102,high:100}),0);});
check('opposite slow slope rejected',()=>{let s=armed();assert.equal(step(s,2,{slowPast:101,high:100}),0);});
check('pair interval exceeded',()=>{let s=state();step(s,0,{cross:-1});step(s,11,{breakout:-1,rangeValid:true});step(s,12);assert.equal(step(s,13,{high:100}),0);});
check('expiration',()=>{let s=armed();assert.equal(step(s,31,{high:100}),0);});
check('reverse cross invalidates old setup',()=>{let s=armed();assert.equal(step(s,2,{cross:1,high:100}),0);});
check('breakout can precede cross',()=>{let s=state();step(s,0,{breakout:-1,rangeValid:true});step(s,5,{cross:-1});step(s,6);assert.equal(step(s,7,{high:100}),-1);});
check('cross can precede breakout',()=>{let s=state();step(s,0,{cross:-1});step(s,5,{breakout:-1,rangeValid:true});step(s,6);assert.equal(step(s,7,{high:100}),-1);});
check('gap beyond touch band is not touch',()=>{let s=armed();assert.equal(step(s,2,{low:103,high:105,close:104}),0);});
check('current tick cannot commit departure to base state',()=>{let s=armed();s.departed=false;let trial={...s};step(trial,2);assert.equal(s.departed,false);assert.equal(step({...s},2,{low:100,high:100,close:100}),0);});
check('symmetric buy',()=>{let s=state();let base={fast:100,slow:98,fastPast:99,slowPast:97,low:106,high:107,close:106};step(s,0,{...base,cross:1,breakout:1,rangeValid:true});step(s,1,base);assert.equal(step(s,2,{...base,low:100.5,high:102,close:101}),1);});
check('range must be valid',()=>{let s=state();step(s,0,{cross:-1,breakout:-1});step(s,1);assert.equal(step(s,2,{high:100}),0);});
check('range boundary break is frozen until expiry',()=>{let s=armed();step(s,5,{breakout:-1,rangeValid:true});assert.equal(s.breakBar,0);});
check('touch tolerance is inclusive',()=>{let s=armed();assert.equal(step(s,2,{low:98,high:99}),-1);});
check('runtime closed candle cannot create touch or consume cross',()=>{
 let s=armed();assert.equal(ctx.FRCommit(s,bar(2,{high:100}),p,false),0);
 assert.equal(s.consumed,false);assert.equal(s.departed,true);
 assert.equal(step(s,3,{low:99.5,high:99.5,close:99.5}),-1);
});
check('runtime close still confirms departure',()=>{
 let s=state();ctx.FRCommit(s,bar(0,{cross:-1,breakout:-1,rangeValid:true}),p,false);
 ctx.FRCommit(s,bar(1),p,false);assert.equal(s.departed,true);
});
check('live signal retained when close no longer touches',()=>{
 let s=armed();assert.equal(step(s,2,{high:100}),-1);
 let replay=armed();replay.consumed=true;
 assert.equal(ctx.FRCommit(replay,bar(2,{low:90,high:91,close:90}),p,false),0);
 assert.equal(replay.consumed,true);assert.equal(step(replay,3,{high:100}),0);
});
check('reverse cross at close resets consumed prior generation',()=>{
 let s=armed();s.consumed=true;
 ctx.FRCommit(s,bar(2,{cross:1}),p,false);
 assert.equal(s.crossDir,1);assert.equal(s.consumed,false);
});
console.log(checks+' core scenarios passed');
module.exports={passed:checks,ctx,p,bar};
