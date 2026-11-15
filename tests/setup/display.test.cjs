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
test('fit scales the whole plate within both dimensions without stretching or enlarging',()=>{
 for(const [w,h,aw,ah] of [[3000,2000,1200,500],[1500,3200,900,600],[900,500,280,200],[600,400,1200,900]]){
   const scale=V.fitScale(w,h,aw,ah);
   assert.ok(scale>0&&scale<=1);assert.ok(w*scale<=aw+1e-8);assert.ok(h*scale<=ah+1e-8);
 }
 assert.equal(V.fitScale(3000,2000,1200,500),0.25);
 assert.equal(V.fitScale(600,400,1200,900),1);
 assert.equal(V.fitScale(0,400,1200,900),1);
});
test('existing display preferences default to fitting and explicit actual-size choice persists across presets',()=>{
 assert.equal(V.normalize({width:240,crop:true}).fit,true);
 assert.equal(V.normalize({fit:false}).fit,false);
 assert.equal(V.preset('details',{fit:false}).fit,false);
});
