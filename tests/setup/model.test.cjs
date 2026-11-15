const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const M=require('../../src/setup/model.js');
const spec=(name='Sample')=>({Name:name,Type:'Sample',Color:'#68b9a2',SetupRecipe:[{name:'Buffer',volume:135,concentration:'50 mM'},{name:'Reagent',volume:15,concentration:'10 µM final'}]});
test('import and backup preserve zero concentrations, labels, metadata and recipes',()=>{
 const p=M.newProject(); const a=M.condition(p,spec());M.assign(p,[0,1,2],a,0,0,'µM');p.layout[1][a].CustomMetadata={test:true};
 const q=M.importProject(p.layout);assert.deepEqual(q.layout,p.layout);assert.equal(M.cells(q)[0].value,0);
 const r=M.importProject({format:'plate-setup',version:1,project:p});assert.deepEqual(r.layout,p.layout);assert.equal(M.recipeTotal(r.layout[1][0].SetupRecipe).total,150);
});
test('replicate blocks respect direction, spacing, boundaries, and group gaps',()=>{
 const p=M.newProject();assert.deepEqual(M.block(p,0,3,'horizontal',1,2,1),[[0,2,4],[24,26,28]]);
 assert.deepEqual(M.block(p,0,3,'vertical',1,2,1),[[0,24,48],[2,26,50]]);
 assert.throws(()=>M.block(p,11,3));assert.throws(()=>M.block(p,0,1.5));assert.throws(()=>M.block(p,0,3,'horizontal',0,9));
});
test('placement protects occupied, concentration-only and used wells',()=>{
 const p=M.newProject();const a=M.condition(p,spec()),b=M.condition(p,spec('Another'));
 M.assign(p,[0],a,0,0,'µM');assert.throws(()=>M.assign(p,[0],b),/already contains/);
 p.layout[0].Layers[0].push({Index:5,Value:0,Unit:'µM'});assert.throws(()=>M.assign(p,[5],b),/already contains/);
 p.locked=[12];assert.throws(()=>M.assign(p,[12],b),/marked used/);assert.throws(()=>M.clear(p,[12]),/Unlock/);
});
test('assignment and clear keep well tags and concentrations in agreement',()=>{
 const p=M.newProject(),a=M.condition(p,spec());M.assign(p,[0,1,2,2],a,0,10,'µM');M.assign(p,[1],a,0,0,'mM');
 assert.equal(p.layout[1][a].Tags[0].Wells.length,3);assert.equal(M.cells(p)[1].value,0);
 M.clear(p,[1]);assert.equal(M.cells(p)[1].areaIndex,null);assert.equal(M.cells(p)[1].value,null);assert.equal(M.cells(p)[0].value,10);
});
test('multiple layers and indexed ranges survive untouched',()=>{
 const layout=[{Rows:8,Cols:12,Layers:[[],[]]},[{Name:'Range',Type:'Range',Color:'red',Custom:true,Replicates:3,Tags:[{Layer:1,Wells:[{Index:4,RangeIndex:7}]}]}]];
 const p=M.importProject(layout);assert.deepEqual(p.layout,layout);assert.equal(M.cells(p,1)[4].rangeIndex,7);assert.equal(M.cells(p,0)[4].areaIndex,null);assert.throws(()=>M.assign(p,[1],0,1),/Ranges/);
});
test('incomplete volumes stay unknown rather than becoming zero',()=>{
 assert.deepEqual(M.recipeTotal([]),{total:null,complete:false});
 assert.deepEqual(M.recipeTotal([{volume:100},{volume:null}]),{total:100,complete:false});
 assert.deepEqual(M.recipeTotal([{volume:0.1},{volume:0.2}]),{total:0.3,complete:true});
 assert.throws(()=>M.validateRecipe([{name:'Buffer',volume:-1,concentration:''}]));
 assert.throws(()=>M.validateRecipe([{name:'',volume:1,concentration:''}]));
});
test('CSV includes each reagent per well and preserves zeros safely',()=>{
 const p=M.newProject(),a=M.condition(p,spec('=1+1'));M.assign(p,[0,1,2],a,0,0,'µM');const csv=M.csv(p);
 assert.equal(csv.split('\r\n').length,7);assert.match(csv,/"A1","'=1\+1"/);assert.match(csv,/"0","µM","Buffer","135"/);assert.match(csv,/"150","Yes"/);
});
test('invalid imports are rejected rather than silently dropping data',()=>{
 assert.throws(()=>M.importProject([{Rows:8,Cols:12,Layers:[[]]},[{Name:'bad',Tags:[{Layer:0,Wells:[{Index:96}]}]}]]));
 assert.throws(()=>M.importProject([{Rows:8,Cols:12,Layers:[[]]},[{Name:'one',Tags:[{Layer:0,Wells:[{Index:0}]}]},{Name:'two',Tags:[{Layer:0,Wells:[{Index:0}]}]}]]));
});
const privateLibrary=path.resolve(__dirname,'../../local-layouts/index.json');
if(fs.existsSync(privateLibrary)){
 const entries=JSON.parse(fs.readFileSync(privateLibrary));
 for(const e of entries)test('local layout round trip: '+e.source,()=>{
   const p=M.importProject(e.layout,e.title);assert.deepEqual(p.layout,e.layout);
   assert.deepEqual(M.importProject({format:'plate-setup',version:1,project:p}).layout,e.layout);
   const expected=e.layout[1].flatMap(a=>a.Tags.flatMap(t=>t.Wells)).length;
   const actual=e.layout[0].Layers.reduce((s,_,i)=>s+M.cells(p,i).filter(c=>c.area).length,0);
   assert.equal(actual,expected);
 });
}
