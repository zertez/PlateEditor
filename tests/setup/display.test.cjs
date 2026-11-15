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
 const p=example(),before=JSON.stringify(p),html=V.wellContent(M.cells(p)[0],V.defaults);
 for(const value of ['Full preparation details that must remain visible','Tagged concentration','0 µM','50 mM final','135 µL','Not recorded','Volume entered','Target volume','150 µL','First line\nSecond line'])assert.ok(html.includes(value),value);
 assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.equal(JSON.stringify(p),before);
});
test('field toggles hide presentation without removing experimental data',()=>{
 const p=example(),cell=M.cells(p)[0],o=V.normalize({fields:{name:false,type:false,tagged:false,notes:false,volumes:false,concentrations:false,totals:false}});
 const html=V.wellContent(cell,o);
 assert.ok(html.includes('Buffer'));assert.ok(!html.includes('135 µL'));assert.ok(!html.includes('Tagged concentration'));assert.ok(!html.includes('First line'));
 assert.equal(cell.area.SetupRecipe[0].volume,135);assert.equal(cell.value,0);
});
test('volumes and concentrations keep their reagent names for context',()=>{
 const p=example(),html=V.wellContent(M.cells(p)[0],V.normalize({fields:{ingredients:false}}));
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
 assert.equal(original.mode,'details');assert.equal(original.width,240);assert.equal(original.font,13);assert.equal(original.wide,false);
 const reset=V.preset('details',original);assert.equal(reset.fields.type,true);assert.equal(JSON.stringify(original),snapshot);
 assert.deepEqual(V.normalize(null),V.defaults);
});
test('notes and recipe data survive project backups',()=>{
 const p=example(),q=M.importProject({format:'plate-setup',version:1,project:p});assert.deepEqual(q.layout,p.layout);
});
test('shared labels group only identical adjacent wells within one row',()=>{
 const p=example(),area=0;
 M.assign(p,[1,3,12,13],area,0,0,'µM');
 p.locked=[3];
 M.assign(p,[4],area,0,5,'µM');
 const cells=M.cells(p),before=JSON.stringify(p),b=V.bounds(cells,p.layout[0],false),groups=V.plateGroups(cells,p.layout[0],b);
 assert.deepEqual(groups[0].cells.map(c=>c.index),[0,1,2]);
 assert.deepEqual(groups[1].cells.map(c=>c.index),[3]);
 assert.deepEqual(groups[2].cells.map(c=>c.index),[4]);
 assert.equal(groups.flatMap(g=>g.cells).length,96);
 assert.equal(new Set(groups.flatMap(g=>g.cells.map(c=>c.index))).size,96);
 assert.ok(groups.every(g=>g.cells.every(c=>Math.floor(c.index/12)===g.row)));
 assert.equal(JSON.stringify(p),before);
});
test('empty columns are narrower without removing coordinates or concentration-only wells',()=>{
 const p=example(),b=V.bounds(M.cells(p),p.layout[0],false);
 const weights=V.columnWeights(M.cells(p),p.layout[0],b);
 assert.equal(weights.length,12);assert.equal(weights[0],1);assert.equal(weights[1],0.25);assert.equal(weights[2],1);
 p.layout[0].Layers[0].push({Index:95,Value:0,Unit:'µM'});
 assert.equal(V.columnWeights(M.cells(p),p.layout[0],b)[11],1);
 const empty=M.newProject();assert.deepEqual(V.columnWeights(M.cells(empty),empty.layout[0],b),Array(12).fill(1));
});
test('readable labels retain full condition strings, volumes and zero values without inventing missing volumes',()=>{
 const p=example(),before=JSON.stringify(p),html=V.readableContent(M.cells(p)[0],V.defaults);
 assert.ok(html.includes('Full preparation details that must remain visible'));
 assert.ok(html.includes('0 µM'));assert.ok(html.includes('Buffer 135 µL'));assert.ok(html.includes('Reagent (volume unknown)'));assert.ok(html.includes('135 µL entered'));
 assert.equal(JSON.stringify(p),before);
 const empty=M.newProject();empty.locked=[0];
 assert.ok(V.readableContent(M.cells(empty)[0],V.defaults).includes('Used / locked'));
});
test('full-detail and contents presets use normal-size text while readable plate enables fitting',()=>{
 assert.equal(V.preset('details',{fit:true}).fit,false);
 assert.equal(V.preset('contents',{fit:true}).fit,false);
 assert.equal(V.preset('overview',{fit:false}).fit,true);
});
test('editor defaults to actual-size text and optional fit preferences remain explicit',()=>{
 assert.equal(V.normalize({width:240,crop:true}).fit,false);
 assert.equal(V.normalize({fit:true}).fit,true);
 assert.equal(V.normalize({fit:false}).fit,false);
 assert.equal(V.preset('details',{fit:false}).fit,false);
});

test('one-page export retains all chosen well details and coordinates independently of the screen mode',()=>{
 const p=example(),before=JSON.stringify(p),html=V.printWhole(p,0,{...V.defaults,fit:true,mode:'overview',print:'plate'});
 assert.equal((html.match(/class="print-export-well"/g)||[]).length,96);
 for(let i=0;i<96;i++)assert.equal((html.match(new RegExp('<strong>'+M.wellName(i,12)+'</strong>','g'))||[]).length,1);
 for(const value of ['Full preparation details that must remain visible','0 µM','135 µL','Not recorded','Target volume','150 µL'])assert.ok(html.includes(value),value);
 assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.equal(JSON.stringify(p),before);
 assert.equal((V.printWhole(p,0,{crop:true}).match(/class="print-export-well"/g)||[]).length,9);
});
