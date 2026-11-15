const {test}=require('node:test');
const assert=require('node:assert/strict');
const M=require('../../src/setup/model.js');
const V=require('../../src/setup/display.js');
function example(){
 const p=M.newProject('Display test');
 const a=M.condition(p,{Name:'Long condition | Full preparation details that must remain visible',Type:'Sample',Color:'#68b9a2',SetupNotes:'First line\nSecond line <script>not executable</script>',SetupTargetVolume:150,SetupRecipe:[{name:'Buffer',volume:135,concentration:'50 mM final'},{name:'Reagent',volume:null,concentration:'Not yet entered'}]});
 M.assign(p,[0,2,24],a,0,0,'µM');return p;
}
test('full details preserve long names, zero concentration, notes, unknown volumes and targets',()=>{
 const p=example(),before=JSON.stringify(p),html=V.wellContent(M.cells(p)[0],{...V.defaults,mode:'details'});
 for(const value of ['Full preparation details that must remain visible','Tagged concentration','0 µM','50 mM final','135 µL','Not recorded','Volume entered','Target volume','150 µL','First line\nSecond line'])assert.ok(html.includes(value),value);
 assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.equal(JSON.stringify(p),before);
});
test('field toggles hide presentation without removing experimental data',()=>{
 const p=example(),cell=M.cells(p)[0],o=V.normalize({mode:'details',fields:{name:false,type:false,tagged:false,notes:false,volumes:false,concentrations:false,totals:false}});
 const html=V.wellContent(cell,o);
 assert.ok(html.includes('Buffer'));assert.ok(!html.includes('135 µL'));assert.ok(!html.includes('Tagged concentration'));assert.ok(!html.includes('First line'));
 assert.equal(cell.area.SetupRecipe[0].volume,135);assert.equal(cell.value,0);
});
test('volumes and concentrations keep their reagent names for context',()=>{
 const p=example(),html=V.wellContent(M.cells(p)[0],V.normalize({mode:'details',fields:{ingredients:false}}));
 assert.ok(html.includes('Buffer'));assert.ok(html.includes('135 µL'));assert.ok(html.includes('50 mM final'));
});
test('crop hides only empty outer space and keeps interior gaps and zero-value wells',()=>{
 const p=example();assert.deepEqual(V.bounds(M.cells(p),p.layout[0],true),{firstRow:0,lastRow:2,firstCol:0,lastCol:2});
 p.layout[0].Layers[0].push({Index:95,Value:0,Unit:'µM'});assert.equal(V.bounds(M.cells(p),p.layout[0],true).lastCol,11);
 const empty=M.newProject();assert.deepEqual(V.bounds(M.cells(empty),empty.layout[0],true),{firstRow:0,lastRow:7,firstCol:0,lastCol:11});
});
test('readable print includes every well exactly once and retains all detail fields',()=>{
 const p=example(),html=V.printSections(p,0,V.defaults);
 assert.equal((html.match(/class="print-section"/g)||[]).length,3);
 for(let i=0;i<96;i++)assert.equal((html.match(new RegExp('<strong>'+M.wellName(i,12)+'</strong>','g'))||[]).length,1);
 assert.ok(html.includes('First line\nSecond line'));assert.ok(html.includes('0 µM'));
 const cropped=V.printSections(p,0,{...V.defaults,crop:true});assert.ok(cropped.includes('<strong>C3</strong>'));assert.ok(!cropped.includes('<strong>D1</strong>'));
});
test('display preferences are bounded and independent of presets',()=>{
 const original=V.normalize({mode:'invalid',width:9000,font:-1,wide:'yes',fields:{type:false}}),snapshot=JSON.stringify(original);
 assert.equal(original.mode,'overview');assert.equal(original.width,240);assert.equal(original.font,13);assert.equal(original.wide,false);
 const reset=V.preset('details',original);assert.equal(reset.fields.type,true);assert.equal(JSON.stringify(original),snapshot);
 assert.deepEqual(V.normalize(null),V.defaults);
});
test('notes and recipe data survive project backups',()=>{
 const p=example(),q=M.importProject({format:'plate-setup',version:1,project:p});assert.deepEqual(q.layout,p.layout);
});
test('compact overview shows original condition numbers and concentrations without expanding recipes',()=>{
 const p=example(),before=JSON.stringify(p),html=V.wellContent(M.cells(p)[0],V.defaults);
 assert.equal(V.defaults.mode,'overview');
 assert.ok(html.includes('class="well-code">1</span>'));assert.ok(html.includes('0 µM'));
 assert.ok(!html.includes('Full preparation details'));assert.ok(!html.includes('Buffer'));
 assert.equal(JSON.stringify(p),before);
 const empty=M.newProject();empty.locked=[0];
 assert.ok(V.wellContent(M.cells(empty)[0],V.defaults).includes('A1 · used'));
});
test('saved oversized views reset to the compact overview once, retaining export preferences',()=>{
 const old={mode:'details',wide:true,crop:true,print:'plate',fields:{notes:false}};
 const restored=V.restore(old);
 assert.equal(restored.mode,'overview');assert.equal(restored.wide,false);assert.equal(restored.crop,false);
 assert.equal(restored.print,'plate');assert.equal(restored.fields.notes,false);assert.equal(old.mode,'details');
 const explicit=V.preset('details',restored);
 assert.equal(V.restore(explicit).mode,'details');assert.deepEqual(V.restore(null),V.defaults);
});

test('one-page export retains all chosen well details and coordinates independently of the screen mode',()=>{
 const p=example(),before=JSON.stringify(p),html=V.printWhole(p,0,{...V.defaults,mode:'overview',print:'plate'});
 assert.equal((html.match(/class="print-export-well"/g)||[]).length,96);
 for(let i=0;i<96;i++)assert.equal((html.match(new RegExp('<strong>'+M.wellName(i,12)+'</strong>','g'))||[]).length,1);
 for(const value of ['Full preparation details that must remain visible','0 µM','135 µL','Not recorded','Target volume','150 µL'])assert.ok(html.includes(value),value);
 assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.equal(JSON.stringify(p),before);
 assert.equal((V.printWhole(p,0,{crop:true}).match(/class="print-export-well"/g)||[]).length,9);
});
