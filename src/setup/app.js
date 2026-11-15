/* Browser-local plate library and direct plate setup. No network data writes. */
(() => {
  'use strict';
  const M=PlateSetup, $=id=>document.getElementById(id), KEY='plate-setup.library.v1';
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const color=c=>/^#[0-9a-f]{6}$/i.test(c)?c:'#a0b7a8';
  const fmt=n=>Number(n).toLocaleString(undefined,{maximumFractionDigits:6});
  let library={version:1,projects:[],active:null}, storageOK=true, selection=new Set(), anchor=null, layer=0, editIndex=null, mode=null, contents=false, drag=null;
  const histories=new Map();
  function project(){return library.projects.find(p=>p.id===library.active);}
  function tell(message,error=false){$('notice').textContent=message;$('notice').hidden=false;$('notice').classList.toggle('error',error);}
  function persist(){
    try{localStorage.setItem(KEY,JSON.stringify(library));storageOK=true;$('save-state').textContent='✓ Saved in this browser';}
    catch(e){storageOK=false;$('save-state').textContent='Not saved — download a backup';tell('Browser storage is unavailable or full. Your work is still open; download a backup before closing.',true);}
  }
  function history(){if(!histories.has(library.active))histories.set(library.active,{undo:[],redo:[]});return histories.get(library.active);}
  function change(fn,message){
    try{const current=project(), next=M.clone(current);fn(next);M.validateLayout(next.layout);const h=history();h.undo.push(M.clone(current));if(h.undo.length>60)h.undo.shift();h.redo=[];library.projects[library.projects.indexOf(current)]=next;persist();render();if(message)tell(message);return true;}
    catch(e){tell(e.message,true);return false;}
  }
  function navigate(id){library.active=id;layer=0;selection.clear();anchor=null;mode=null;editIndex=null;resetForm();persist();render();}
  function totalLabel(a){const t=M.recipeTotal(a?.SetupRecipe);return t.total===null?'Recipe not entered':`${fmt(t.total)} µL${t.complete?'':' entered · incomplete'}`;}
  function render(){
    const p=project();if(!p)return;
    $('project-title').value=p.title;$('project-notes').value=p.notes||'';
    $('project-list').innerHTML=library.projects.map(q=>`<button class="project ${q.id===p.id?'active':''}" data-project="${esc(q.id)}" ${q.id===p.id?'aria-current="true"':''}>${esc(q.title)}<small>${q.layout[0].Rows*q.layout[0].Cols} wells · ${q.layout[1].length} conditions</small></button>`).join('');
    $('layer').innerHTML=p.layout[0].Layers.map((_,i)=>`<option value="${i}" ${i===layer?'selected':''}>${i+1}</option>`).join('');
    const view=M.cells(p,layer), used=view.filter(c=>c.area||c.value!==null).length;
    $('plate-summary').textContent=`${p.layout[0].Rows} rows × ${p.layout[0].Cols} columns · ${used} wells assigned · ${p.locked.length} marked used`;
    $('plate-size').textContent=`${view.length}-well plate`;
    $('condition-count').textContent=p.layout[1].length;
    $('conditions').innerHTML=p.layout[1].length?p.layout[1].map((a,i)=>{
      const n=a.Tags.reduce((s,t)=>s+t.Wells.length,0);
      const recipe=a.SetupRecipe||[];
      const detail=recipe.length?recipe.map(r=>`${r.name}${r.concentration?' ('+r.concentration+')':''}: ${r.volume===null?'volume not entered':fmt(r.volume)+' µL'}`).join(' · '):'Add reagents and volumes to describe everything in each well';
      return `<button class="condition-row ${editIndex===i?'active':''}" data-condition="${i}" style="--well-color:${color(a.Color)}"><span class="condition-swatch">${i+1}</span><span class="condition-label">${esc(a.Name)}<small>${esc(detail)}</small></span><span class="condition-count">${n} wells<br>${esc(totalLabel(a))}</span></button>`;
    }).join(''):'<div class="empty-state">Start with a condition and its ingredients.<br>Then place it in the wells you want.</div>';
    $('undo').disabled=!history().undo.length;$('redo').disabled=!history().redo.length;
    renderGrid();renderSelection();
  }
  function renderGrid(){
    const p=project(),plate=p.layout[0],view=M.cells(p,layer), grid=$('plate-grid');grid.style.setProperty('--cols',plate.Cols);document.body.classList.toggle('contents-view',contents);
    let html='<span></span>'+Array.from({length:plate.Cols},(_,i)=>`<button class="axis" data-col="${i}" aria-label="Select column ${i+1}">${i+1}</button>`).join('');
    view.forEach((c,i)=>{if(i%plate.Cols===0)html+=`<button class="axis" data-row="${Math.floor(i/plate.Cols)}" aria-label="Select row ${M.rowName(Math.floor(i/plate.Cols))}">${M.rowName(Math.floor(i/plate.Cols))}</button>`;
      const a=c.area,rec=a?.SetupRecipe||[];
      let content=a?`<span class="well-code">${c.areaIndex+1}${c.locked?' · used':''}</span><span class="well-dose">${c.value===null?'':esc(fmt(c.value)+' '+c.unit)}</span>`:`<span>${c.name}${c.locked?' · used':''}</span>${c.value===null?'':`<span>${esc(fmt(c.value)+' '+c.unit)}</span>`}`;
      if(contents && a)content=`<span class="well-code">${c.name} · ${c.areaIndex+1}${c.locked?' · used':''}</span><span class="well-title">${esc(a.Name)}</span><span class="well-recipe">${rec.length?rec.map(r=>`<span class="ingredient"><span>${esc(r.name)}${r.concentration?`<span>${esc(r.concentration)}</span>`:''}</span><strong>${r.volume===null?'—':fmt(r.volume)+' µL'}</strong></span>`).join(''):'Recipe not entered'}<span><strong>${esc(totalLabel(a))}</strong></span></span>`;
      const title=`${c.name}: ${a?a.Name:'Unassigned'}${c.value!==null?' · '+c.value+' '+c.unit:''}${rec.length?'\n'+rec.map(r=>`${r.name}: ${r.volume===null?'not entered':r.volume+' µL'}${r.concentration?' ('+r.concentration+')':''}`).join('\n'):''}${c.locked?' · Used / locked':''}`;
      html+=`<button class="well ${a?'occupied':'empty'} ${c.locked?'locked':''}" data-well="${i}" aria-label="${esc(title)}" aria-pressed="${selection.has(i)}" title="${esc(title)}" style="--well-color:${color(a?.Color)}">${content}</button>`;
    });grid.innerHTML=html;
  }
  function renderSelection(){
    const p=project();if(!p)return;
    document.querySelectorAll('[data-well]').forEach(b=>{const active=selection.has(+b.dataset.well);b.classList.toggle('selected',active);b.setAttribute('aria-pressed',active);});
    const names=[...selection].sort((a,b)=>a-b).map(i=>M.wellName(i,p.layout[0].Cols));
    $('selection-label').textContent=names.length?`${names.length} selected · ${names.slice(0,5).join(', ')}${names.length>5?'…':''}`:'No wells selected';
    $('clear-wells').disabled=!names.length;$('lock-wells').disabled=!names.length;$('assign-selected').disabled=!names.length;
    $('lock-wells').textContent=names.length&&[...selection].every(i=>p.locked.includes(i))?'Unlock wells':'Mark used';
    $('mode-hint').textContent=mode?'Hover to preview · click a starting well · Esc to cancel':'Click a well to see its contents';
    $('place-mode').textContent=mode==='replicates'?'Cancel placement':'Place replicates →';
    const i=selection.size?[...selection].at(-1):null;
    if(i===null){$('well-details').innerHTML='<p class="eyebrow">WELL CONTENTS</p><h2>Select a well</h2><p class="muted">See every reagent and its volume here.</p>';return;}
    const c=M.cells(p,layer)[i],a=c.area,rec=a?.SetupRecipe||[];
    $('well-details').innerHTML=`<p class="eyebrow">WELL CONTENTS${selection.size>1?' · LAST SELECTED':''}</p><h2>${c.name}${c.locked?' <small>Used / locked</small>':''}</h2><p class="well-full-name">${esc(a?.Name||'Unassigned well')}</p>${c.value===null?'':`<p class="muted">Tagged concentration: ${esc(fmt(c.value)+' '+c.unit)}</p>`}${rec.length?`<table class="contents-table"><thead><tr><th>Reagent</th><th>Volume</th></tr></thead><tbody>${rec.map(r=>`<tr><td>${esc(r.name)}${r.concentration?`<small>${esc(r.concentration)}</small>`:''}</td><td>${r.volume===null?'Not entered':fmt(r.volume)+' µL'}</td></tr>`).join('')}</tbody></table><div class="recipe-total"><span>${M.recipeTotal(rec).complete?'Total per well':'Total entered (incomplete)'}</span><strong>${esc(totalLabel(a))}</strong></div>`:'<p class="muted" style="margin-top:12px">No ingredient volumes recorded yet.</p>'}${a?.SetupTargetVolume!=null?`<p class="muted">Target: ${fmt(a.SetupTargetVolume)} µL</p>`:''}${a?`<button class="full" data-edit-well="${c.areaIndex}">Edit this condition’s recipe</button>`:''}`;
  }
  function addReagent(r={name:'',volume:null,concentration:''}){
    const row=document.createElement('div');row.className='reagent';row.innerHTML=`<input class="reagent-name" aria-label="Reagent name" placeholder="Reagent name" value="${esc(r.name)}"><input class="reagent-volume" aria-label="Reagent volume in µL" type="number" min="0" step="any" placeholder="µL" value="${r.volume??''}"><input class="reagent-concentration" aria-label="Reagent concentration or note" placeholder="Concentration / note (optional)" value="${esc(r.concentration)}"><button type="button" aria-label="Remove reagent">×</button>`;row.querySelector('button').onclick=()=>{row.remove();updateTotal();stashDraft();};$('recipe-rows').append(row);updateTotal();
  }
  function readRecipe(){return [...document.querySelectorAll('.reagent')].map(row=>({name:row.querySelector('.reagent-name').value.trim(),volume:row.querySelector('.reagent-volume').value===''?null:Number(row.querySelector('.reagent-volume').value),concentration:row.querySelector('.reagent-concentration').value.trim()})).filter(r=>r.name||r.volume!==null||r.concentration);}
  function updateTotal(){const rec=readRecipe(),t=M.recipeTotal(rec);$('recipe-total').textContent=t.total===null?'—':`${fmt(t.total)} µL${t.complete?'':' (incomplete)'}`;const target=$('target-volume').value;$('volume-check').textContent=target!==''&&t.total!==null?`${fmt(Math.abs(Number(target)-t.total))} µL ${t.total>Number(target)?'over target':'remaining to target'}${!t.complete?' · some volumes are blank':''}`:'';}
  function draft(){return {editIndex,Name:$('condition-name').value,Color:$('condition-color').value,Type:$('condition-type').value,SetupRecipe:readRecipe(),SetupTargetVolume:$('target-volume').value,tag:$('tag-value').value,unit:$('tag-unit').value};}
  function stashDraft(){if(project()){project().draft=draft();persist();}}
  function resetForm(){editIndex=null;mode=null;$('condition-name').value='';$('condition-color').value=M.colors[(project()?.layout[1].length||0)%M.colors.length];$('condition-type').value='Sample';$('recipe-rows').innerHTML='';$('target-volume').value='';$('tag-value').value='';$('tag-unit').value='µM';$('composer-heading').textContent='New condition';$('save-condition').textContent='Save condition';addReagent();}
  function editCondition(i){
    const a=project().layout[1][i];if(a.Type==='Range'){tell('This condition is an indexed range. Its data is preserved; use the original editor to edit ranges.',true);return;}
    editIndex=i;mode=null;$('condition-name').value=a.Name;$('condition-color').value=color(a.Color);$('condition-type').value=['Sample','Positive Control','Negative Control'].includes(a.Type)?a.Type:'Sample';$('recipe-rows').innerHTML='';(a.SetupRecipe?.length?a.SetupRecipe:[{}]).forEach(r=>addReagent({name:r.name||'',volume:r.volume??null,concentration:r.concentration||''}));$('target-volume').value=a.SetupTargetVolume??'';
    const tagged=M.cells(project(),layer).filter(c=>c.areaIndex===i), first=tagged[0];const same=tagged.every(c=>c.value===first?.value && c.unit===first?.unit);
    $('tag-value').value=same?(first?.value??''):'';$('tag-unit').value=same?(first?.unit||'µM'):'µM';
    $('composer-heading').textContent=`Edit condition ${i+1}`;$('save-condition').textContent='Save recipe to all its wells';updateTotal();stashDraft();render();
  }
  function spec(){
    const s={Name:$('condition-name').value.trim(),Color:$('condition-color').value,Type:$('condition-type').value,SetupRecipe:readRecipe(),SetupTargetVolume:$('target-volume').value===''?null:Number($('target-volume').value)};
    M.validateRecipe(s.SetupRecipe);if(!s.Name)throw Error('Give the condition a name first.');return s;
  }
  function tagValue(){const v=$('tag-value').value;return v===''?null:Number(v);}
  function saveCondition(){const s=spec();let idx;const ok=change(p=>{idx=M.condition(p,s,editIndex);delete p.draft;},'Condition and recipe saved. All wells using this condition now show the updated contents.');if(ok){editIndex=idx;$('composer-heading').textContent=`Edit condition ${idx+1}`;$('save-condition').textContent='Save recipe to all its wells';stashDraft();render();}return ok;}
  function plan(start){const groups=mode==='series'?$('series-values').value.split(',').map(s=>s.trim()):null;
    if(groups && (groups.some(s=>s===''||!Number.isFinite(Number(s))||Number(s)<0)||new Set(groups.map(Number)).size!==groups.length))throw Error('Enter distinct, non-negative concentration values separated by commas.');
    return {values:groups?.map(Number),blocks:M.block(project(),start,Number($('replicates').value),$('direction').value,Number($('well-gap').value),groups?.length||1,Number($('group-gap').value))};
  }
  function preview(start){document.querySelectorAll('.preview').forEach(b=>b.classList.remove('preview','invalid'));try{const p=plan(start);let invalid=false;try{M.ensureEditable(project(),p.blocks.flat(),layer);}catch(e){invalid=true;$('mode-hint').textContent=e.message;}
      p.blocks.flat().forEach(i=>{const b=document.querySelector(`[data-well="${i}"]`);b?.classList.add('preview');if(invalid)b?.classList.add('invalid');});if(!invalid)$('mode-hint').textContent=`Click to place ${p.blocks.flat().length} wells starting at ${M.wellName(start,project().layout[0].Cols)}`;
    }catch(e){$('mode-hint').textContent=e.message;}}
  function place(start){try{const s=spec(),p=plan(start),wasSeries=mode==='series';let idx=editIndex;
    const ok=change(next=>{M.ensureEditable(next,p.blocks.flat(),layer);if(wasSeries){p.blocks.forEach((indices,n)=>{const value=p.values[n],a=M.condition(next,{...s,Name:`${s.Name} · ${value} ${$('tag-unit').value}`});M.assign(next,indices,a,layer,value,$('tag-unit').value);});}else{idx=M.condition(next,s,editIndex);M.assign(next,p.blocks[0],idx,layer,tagValue(),$('tag-unit').value);}delete next.draft;},`Placed ${p.blocks.flat().length} wells. You can change their recipe by clicking the condition below.`);
    if(ok){selection=new Set(p.blocks.flat());mode=null;if(!wasSeries)editCondition(idx);render();document.querySelector('.inspector').scrollTo({top:0});}
    }catch(e){tell(e.message,true);}}
  function download(data,name,type='application/json'){const u=URL.createObjectURL(new Blob([data],{type})),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);}
  const fileName=()=>project().title.replace(/[^\p{L}\p{N}._ -]/gu,'_').slice(0,150)||'Plate';
  $('project-list').onclick=e=>{const b=e.target.closest('[data-project]');if(b){stashDraft();navigate(b.dataset.project);restoreDraft();}};
  $('conditions').onclick=e=>{const b=e.target.closest('[data-condition]');if(b)editCondition(+b.dataset.condition);};
  $('well-details').onclick=e=>{const b=e.target.closest('[data-edit-well]');if(b)editCondition(+b.dataset.editWell);};
  $('add-condition').onclick=$('reset-condition').onclick=()=>{resetForm();stashDraft();render();$('condition-name').focus();};
  $('variant-condition').onclick=()=>{const name=$('condition-name').value;editIndex=null;mode=null;$('condition-name').value=name?name+' (variant)':'';$('condition-color').value=M.colors[project().layout[1].length%M.colors.length];$('composer-heading').textContent='New variant';$('save-condition').textContent='Save condition';stashDraft();render();tell('This is an independent recipe. Rename or change its ingredients, then place it in empty wells.');};
  $('add-reagent').onclick=()=>{addReagent();stashDraft();};
  $('condition-form').oninput=()=>{updateTotal();stashDraft();};
  $('condition-form').onsubmit=e=>{e.preventDefault();try{saveCondition();}catch(err){tell(err.message,true);}};
  $('place-mode').onclick=()=>{try{spec();mode=mode==='replicates'?null:'replicates';renderSelection();tell(mode?'Move over an empty well to preview your replicates, then click to place.':'Placement cancelled.');}catch(e){tell(e.message,true);}};
  $('series-mode').onclick=()=>{try{spec();mode='series';plan(0);renderSelection();tell('Hover over the plate to preview the series. Each group gets the next tagged concentration; review reagent volumes for each group.');}catch(e){mode=null;tell(e.message,true);}};
  $('assign-selected').onclick=()=>{try{const s=spec();let idx;const ok=change(p=>{idx=M.condition(p,s,editIndex);M.assign(p,[...selection],idx,layer,tagValue(),$('tag-unit').value);delete p.draft;},'Condition applied to the selected wells.');if(ok)editCondition(idx);}catch(e){tell(e.message,true);}};
  const grid=$('plate-grid');
  grid.onpointerdown=e=>{const b=e.target.closest('[data-well]');if(!b||mode||e.button!==0)return;const i=+b.dataset.well;
    if(e.shiftKey&&anchor!==null)selection=new Set(M.rectangle(anchor,i,project().layout[0].Cols));
    else if(e.metaKey||e.ctrlKey){selection.has(i)?selection.delete(i):selection.add(i);anchor=i;}
    else{selection=new Set([i]);anchor=i;drag=i;}
    renderSelection();document.querySelector('.inspector').scrollTo({top:0});};
  grid.onpointerover=e=>{const b=e.target.closest('[data-well]');if(!b)return;const i=+b.dataset.well;if(mode)preview(i);else if(drag!==null&&e.buttons===1){selection=new Set(M.rectangle(drag,i,project().layout[0].Cols));renderSelection();}};
  window.addEventListener('pointerup',()=>{drag=null;});
  grid.onclick=e=>{const b=e.target.closest('[data-well]');if(b){const i=+b.dataset.well;if(mode)place(i);else if(e.detail===0){selection=new Set([i]);anchor=i;renderSelection();}return;}
    const row=e.target.closest('[data-row]'),col=e.target.closest('[data-col]'),p=project().layout[0];if(row)selection=new Set(Array.from({length:p.Cols},(_,i)=>+row.dataset.row*p.Cols+i));if(col)selection=new Set(Array.from({length:p.Rows},(_,i)=>i*p.Cols + +col.dataset.col));renderSelection();};
  grid.onkeydown=e=>{const b=e.target.closest('[data-well]');if(!b)return;let next=+b.dataset.well;const cols=project().layout[0].Cols;const offsets={ArrowLeft:-1,ArrowRight:1,ArrowUp:-cols,ArrowDown:cols};if(e.key in offsets){e.preventDefault();next+=offsets[e.key];document.querySelector(`[data-well="${next}"]`)?.focus();}};
  $('select-clear').onclick=()=>{selection.clear();renderSelection();};
  $('clear-wells').onclick=()=>{change(p=>M.clear(p,[...selection],layer),'Selected wells cleared. Undo is available.');};
  $('lock-wells').onclick=()=>{change(p=>{const unlock=[...selection].every(i=>p.locked.includes(i));p.locked=unlock?p.locked.filter(i=>!selection.has(i)):[...new Set([...p.locked,...selection])];},'Used-well protection updated.');};
  $('layer').onchange=()=>{layer=+$('layer').value;selection.clear();mode=null;render();};
  function historyMove(from,to){const h=history();if(!h[from].length)return;h[to].push(M.clone(project()));const p=h[from].pop();library.projects[library.projects.findIndex(q=>q.id===p.id)]=p;mode=null;editIndex=null;resetForm();persist();render();tell(from==='undo'?'Change undone.':'Change restored.');}
  $('undo').onclick=()=>historyMove('undo','redo');$('redo').onclick=()=>historyMove('redo','undo');
  document.addEventListener('keydown',e=>{if(e.key==='Escape'){mode=null;document.querySelectorAll('.preview').forEach(b=>b.classList.remove('preview','invalid'));renderSelection();}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'&&!['INPUT','TEXTAREA','SELECT'].includes(e.target.tagName)){e.preventDefault();e.shiftKey?historyMove('redo','undo'):historyMove('undo','redo');}});
  $('project-title').onchange=()=>change(p=>{p.title=$('project-title').value.trim()||'Untitled plate';});
  $('project-notes').oninput=()=>{project().notes=$('project-notes').value;persist();};
  $('view-compact').onclick=()=>setView(false);$('view-contents').onclick=()=>setView(true);
  function setView(value){contents=value;$('view-compact').classList.toggle('active',!value);$('view-contents').classList.toggle('active',value);$('view-compact').setAttribute('aria-pressed',!value);$('view-contents').setAttribute('aria-pressed',value);renderGrid();renderSelection();}
  $('backup').onclick=()=>download(JSON.stringify({format:'plate-setup',version:1,project:project()},null,2),fileName()+'.plate.json');
  $('export-csv').onclick=()=>download(M.csv(project()),fileName()+'.csv','text/csv;charset=utf-8');
  $('print').onclick=()=>window.print();
  $('duplicate').onclick=()=>{const p=M.clone(project());p.id=M.id();p.title+=' (copy)';library.projects.unshift(p);navigate(p.id);tell('Created an independent copy, including recipes and used-well markings.');};
  $('new-plate').onclick=()=>{$('new-name').value='';$('new-dialog').showModal();$('new-name').focus();};
  $('cancel-new').onclick=()=>$('new-dialog').close();
  $('new-form').onsubmit=e=>{e.preventDefault();const [r,c]=$('new-format').value.split(',').map(Number),p=M.newProject($('new-name').value.trim(),r,c);library.projects.unshift(p);navigate(p.id);$('new-dialog').close();tell('Add a condition and its ingredients, then place it on the plate.');};
  $('import').onclick=()=>$('file-input').click();
  $('file-input').onchange=async()=>{let last=null,errors=[];for(const f of $('file-input').files){try{const p=M.importProject(await f.text(),f.name.replace(/\.(save|plate\.json|json)$/i,'').replaceAll('_',' '));library.projects.unshift(p);last=p.id;}catch(e){errors.push(`${f.name}: ${e.message}`);}}if(last)navigate(last);if(errors.length)tell(errors.join(' '),true);else if(last)tell('Layout imported and saved in your plate library. Add ingredient volumes to complete the recipes.');$('file-input').value='';};
  $('analysis').onclick=e=>{try{sessionStorage.setItem('plate-setup.handoff',JSON.stringify(project().layout));$('analysis').href='Editor.html?setup=1';}catch(err){e.preventDefault();tell('Could not open the original editor. Download a backup before continuing.',true);}};
  function restoreDraft(){const d=project()?.draft;if(!d)return;editIndex=Number.isInteger(d.editIndex)&&project().layout[1][d.editIndex]?d.editIndex:null;$('condition-name').value=d.Name||'';$('condition-color').value=color(d.Color);$('condition-type').value=d.Type||'Sample';$('target-volume').value=d.SetupTargetVolume??'';$('tag-value').value=d.tag??'';$('tag-unit').value=d.unit||'µM';$('recipe-rows').innerHTML='';(d.SetupRecipe?.length?d.SetupRecipe:[{name:'',volume:null,concentration:''}]).forEach(addReagent);$('composer-heading').textContent=editIndex===null?'New condition':`Edit condition ${editIndex+1}`;$('save-condition').textContent=editIndex===null?'Save condition':'Save recipe to all its wells';updateTotal();render();}
  async function start(){
    try{const stored=localStorage.getItem(KEY);if(stored){const parsed=JSON.parse(stored);if(parsed.version!==1||!Array.isArray(parsed.projects))throw Error('Unrecognized plate library.');parsed.projects.forEach(p=>{M.validateLayout(p.layout);if(!Array.isArray(p.locked))throw Error('Invalid used-well markings.');});library=parsed;}}
    catch(e){storageOK=false;tell('The saved library could not be read. It has not been overwritten. Download your browser data or restore a backup before continuing.',true);$('save-state').textContent='Saved library could not be read';return;}
    // Optional untracked local seeds. No scientific layouts are bundled in the public source.
    try{const response=await fetch('local-layouts/index.json');if(response.ok){const entries=await response.json();for(const entry of entries){if(!library.projects.some(p=>p.source===entry.source)){const p=M.importProject(entry.layout,entry.title);p.source=entry.source;library.projects.push(p);}}}}catch(e){/* Offline and hosted installations need no seed library. */}
    if(!library.projects.length){const p=M.newProject('My first plate');library.projects.push(p);}
    if(!project())library.active=library.projects[0].id;
    resetForm();persist();render();restoreDraft();
  }
  start();
})();
