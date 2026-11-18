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
test('successive applications and replicate placements leave earlier wells unchanged',()=>{
 const p=M.newProject();
 const a=M.applyCondition(p,[0,1,2],spec('Control'),null,0,0,'µM');
 const earlier=M.clone(M.cells(p).slice(0,3));
 const b=M.applyCondition(p,M.block(p,12,3)[0],spec('Treatment'),a,0,5,'µM');
 assert.notEqual(a,b);assert.deepEqual(M.cells(p).slice(0,3),earlier);
 const c=M.applyCondition(p,[24,25,26],spec('Third condition'),b,0,10,'µM');
 assert.notEqual(b,c);
 assert.deepEqual([0,12,24].map(i=>[M.cells(p)[i].area.Name,M.cells(p)[i].value]),[['Control',0],['Treatment',5],['Third condition',10]]);
 assert.deepEqual(M.importProject({format:'plate-setup',version:1,project:p}).layout,p.layout);
});
test('editing one shared well creates an independent recipe and preserves other layers and metadata',()=>{
 const p=M.newProject();p.layout[0].Layers.push([]);
 const a=M.condition(p,spec());p.layout[1][a].CustomMetadata={keep:true};
 M.assign(p,[0,1,2],a,0,5,'µM');M.assign(p,[1],a,1,7,'mM');p.locked=[0];
 const otherLayer=M.clone(M.cells(p,1)[1]);
 const updated={...spec(),SetupNotes:'Different mixture',SetupTargetVolume:100,SetupRecipe:[{name:'Buffer',volume:99,concentration:'25 mM'},{name:'Enzyme',volume:1,concentration:'2 µg/µL'}]};
 const b=M.applyCondition(p,[1],updated,a,0,0,'µM');
 const cells=M.cells(p);
 assert.equal(cells[0].areaIndex,a);assert.equal(cells[2].areaIndex,a);assert.equal(cells[1].areaIndex,b);
 assert.equal(cells[0].value,5);assert.equal(cells[1].value,0);
 assert.deepEqual(cells[0].area.SetupRecipe,spec().SetupRecipe);
 assert.equal(cells[1].area.Name,'Sample (variant)');assert.deepEqual(cells[1].area.SetupRecipe,updated.SetupRecipe);
 assert.equal(cells[1].area.SetupNotes,updated.SetupNotes);assert.equal(cells[1].area.SetupTargetVolume,100);
 assert.deepEqual(cells[1].area.CustomMetadata,{keep:true});
 assert.equal(M.cells(p,1)[1].value,otherLayer.value);assert.deepEqual(M.cells(p,1)[1].area.SetupRecipe,otherLayer.area.SetupRecipe);
 assert.deepEqual(p.locked,[0]);M.validateLayout(p.layout);
});
test('unchanged recipes reuse their condition and complete selections can be edited in place',()=>{
 const p=M.newProject(),a=M.applyCondition(p,[0,1,2],spec());
 // Native JSON persistence may reorder dictionary keys on reload.
 p.layout[1][a].SetupRecipe=p.layout[1][a].SetupRecipe.map(r=>({concentration:r.concentration,volume:r.volume,name:r.name}));
 assert.equal(M.applyCondition(p,[12,13,14],{...spec(),SetupNotes:'',SetupTargetVolume:null},a),a);
 assert.equal(p.layout[1].length,1);
 assert.equal(M.applyCondition(p,[0,1,2,12,13,14],spec('Renamed'),a),a);
 assert.equal(p.layout[1].length,1);assert.equal(M.cells(p)[0].area.Name,'Renamed');
});
test('scoped edits check all layers and generate distinct variant names',()=>{
 const p=M.newProject();p.layout[0].Layers.push([]);
 const a=M.applyCondition(p,[0],spec());M.assign(p,[0],a,1);
 M.condition(p,spec('Sample (variant)'));
 const b=M.applyCondition(p,[0],{...spec(),Color:'#123456'},a);
 assert.equal(p.layout[1][b].Name,'Sample (variant 2)');
 assert.equal(M.cells(p,1)[0].area.Color,spec().Color);
 assert.equal(M.cells(p)[0].area.Color,'#123456');
});
test('failed scoped applications are atomic and protect used, unrelated and range wells',()=>{
 const p=M.newProject(),a=M.applyCondition(p,[0,1],spec()),b=M.condition(p,spec('Other'));
 M.assign(p,[2],b);p.locked=[1];p.layout[0].Layers[0].push({Index:3,Value:0,Unit:'µM'});
 const before=M.clone(p);
 for(const indices of [[0,1],[0,2],[0,3],[],[96]]){
   assert.throws(()=>M.applyCondition(p,indices,spec('Changed'),a));assert.deepEqual(p,before);
 }
 assert.throws(()=>M.applyCondition(p,[0],spec('Changed'),a,0,-1,'µM'));assert.deepEqual(p,before);
 assert.throws(()=>M.applyCondition(p,[0],{...spec(),SetupRecipe:[{name:'Bad',volume:-1,concentration:''}]},a));assert.deepEqual(p,before);
 p.layout[1][a].Type='Range';const rangeBefore=M.clone(p);
 assert.throws(()=>M.applyCondition(p,[0],spec('Changed'),a),/ranges/);assert.deepEqual(p,rangeBefore);
});
test('explicit condition-wide saving still updates every well using that condition',()=>{
 const p=M.newProject(),a=M.applyCondition(p,[0,1,2],spec());
 M.condition(p,spec('Shared update'),a);
 assert.deepEqual(M.cells(p).slice(0,3).map(c=>c.area.Name),Array(3).fill('Shared update'));
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

test('changing only an ingredient unit creates a variant for the selected well', () => {
  const project = M.newProject();
  const row = {name: 'Substrate', reagentType: 'reagent', amount: 25, amountUnit: 'µM', volume: null, concentration: ''};
  const recipe = {...spec('Assay'), SetupRecipe: [row]};
  const original = M.condition(project, recipe);
  M.assign(project, [0, 1], original);
  const edited = {...recipe, SetupRecipe: [{...row, amountUnit: 'nM'}]};
  M.applyCondition(project, [1], edited, original);
  const [first, second] = M.cells(project);
  assert.deepEqual(first.area.SetupRecipe, [row]);
  assert.deepEqual(second.area.SetupRecipe, edited.SetupRecipe);
  assert.deepEqual(M.recipeTotal(edited.SetupRecipe), {total: null, complete: false});
});

test('protein mass and molarity retain their units and zeros in backups and CSV', () => {
  const project = M.newProject();
  const protein = {name: 'Protein', reagentType: 'protein', amount: 0, amountUnit: 'µg', volume: 0, concentration: 'lot A'};
  const reagent = {...protein, name: 'Buffer', reagentType: 'reagent', amount: 12, amountUnit: 'mM', volume: null};
  const index = M.condition(project, {...spec('Recipe'), SetupRecipe: [protein, reagent]});
  M.assign(project, [0], index);
  const copy = M.importProject({format: 'plate-setup', version: 1, project});
  assert.deepEqual(copy.layout, project.layout);
  const csv = M.csv(copy);
  assert.match(csv, /"protein","","","0","µg"/);
  assert.match(csv, /"reagent","12","mM","",""/);
  assert.throws(() => M.validateRecipe([{...protein, amountUnit: 'mM'}]));
  assert.throws(() => M.validateRecipe([{...reagent, amount: -1}]));
});
