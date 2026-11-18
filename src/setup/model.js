/* Plate Setup model. Keep the upstream layout intact for lossless imports. */
(function (root) {
  'use strict';
  const clone = value => JSON.parse(JSON.stringify(value));
  const colors = ['#68b9a2','#78aee0','#dda365','#ad91ce','#d58391','#98ae64','#66bfc9','#b49b85'];
  const id = () => globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  function rowName(n) { let s = ''; for (n++; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; }
  const wellName = (index, cols) => rowName(Math.floor(index / cols)) + (index % cols + 1);
  function validateLayout(data) {
    if (!Array.isArray(data) || data.length !== 2 || !data[0] || !Array.isArray(data[1])) throw Error('Choose a PlateEditor layout or a Plate Setup backup.');
    const [p, areas] = data;
    if (![p.Rows,p.Cols].every(n => Number.isInteger(n) && n > 0 && n <= 48) || !Array.isArray(p.Layers) || !p.Layers.length) throw Error('Invalid plate dimensions or layers.');
    const validWell = w => { if (!w || !Number.isInteger(w.Index) || w.Index < 0 || w.Index >= p.Rows*p.Cols || (w.Value != null && (typeof w.Value !== 'number' || !Number.isFinite(w.Value)))) throw Error('Invalid well or concentration in layout.'); };
    p.Layers.forEach(layer => { if (!Array.isArray(layer)) throw Error('Invalid layer.'); layer.forEach(validWell); });
    const occupied = new Set();
    areas.forEach(a => {
      if (!a || typeof a.Name !== 'string' || !Array.isArray(a.Tags)) throw Error('Invalid condition in layout.');
      if (a.SetupRecipe) validateRecipe(a.SetupRecipe);
      a.Tags.forEach(t => {
        if (!Number.isInteger(t.Layer) || t.Layer < 0 || t.Layer >= p.Layers.length || !Array.isArray(t.Wells)) throw Error('Invalid condition layer.');
        t.Wells.forEach(w => { validWell(w); const key = `${t.Layer}:${w.Index}`; if (occupied.has(key)) throw Error('Overlapping conditions in the same layer. Open this file in the original editor.'); occupied.add(key); });
      });
    });
    return data;
  }
  const reagentUnits = {
    reagent: ['µM', 'mM', 'nM', 'pM', 'M'],
    protein: ['µg', 'mg', 'ng', 'pg']
  };
  function validateRecipe(recipe) {
    if (!Array.isArray(recipe)) throw Error('Invalid recipe.');
    for (const row of recipe) {
      if (!row || typeof row.name !== 'string' || !row.name.trim()) throw Error('Give each reagent a name.');
      if (row.volume !== null && (!Number.isFinite(row.volume) || row.volume < 0)) throw Error('Enter a non-negative volume or leave it blank.');
      if (typeof row.concentration !== 'string') throw Error('Invalid reagent note.');
      if (row.reagentType == null && row.amount == null && row.amountUnit == null) continue;
      if (!Object.hasOwn(reagentUnits, row.reagentType) || !reagentUnits[row.reagentType].includes(row.amountUnit))
        throw Error('Choose a unit for this reagent type.');
      if (row.amount !== null && (!Number.isFinite(row.amount) || row.amount < 0))
        throw Error('Enter a non-negative concentration or protein mass.');
    }
    return recipe;
  }
  function newProject(title = 'Untitled plate', rows = 8, cols = 12) {
    return {id:id(), title, notes:'', locked:[], layout:validateLayout([{Rows:rows, Cols:cols, KeepSelected:true, Digits:1, Layers:[[]]}, []])};
  }
  function importProject(input, title = 'Imported plate') {
    const data = typeof input === 'string' ? JSON.parse(input) : clone(input);
    if (data?.format === 'plate-setup' && data.version === 1) {
      const p = data.project; validateLayout(p.layout);
      if (typeof p.title !== 'string' || !Array.isArray(p.locked) || !p.locked.every(i=>Number.isInteger(i) && i>=0 && i<p.layout[0].Rows*p.layout[0].Cols)) throw Error('Invalid project backup.');
      p.id = id(); return p;
    }
    validateLayout(data);
    const locked = new Set();
    data[1].filter(a => /^USED\b/i.test(a.Name)).forEach(a => a.Tags.forEach(t => t.Wells.forEach(w => locked.add(w.Index))));
    return {id:id(),title,notes:'',locked:[...locked],layout:data};
  }
  function cells(project, layer = 0) {
    const [p, areas] = project.layout;
    const out = Array.from({length:p.Rows*p.Cols}, (_,index) => ({index, name:wellName(index,p.Cols), areaIndex:null, value:null, unit:'', locked:project.locked.includes(index)}));
    p.Layers[layer].forEach(w => Object.assign(out[w.Index], {value:w.Value ?? null,unit:w.Unit || '',rangeIndex:w.RangeIndex}));
    areas.forEach((a,areaIndex) => a.Tags.filter(t=>t.Layer===layer).forEach(t=>t.Wells.forEach(w=>Object.assign(out[w.Index],{areaIndex,area:a,rangeIndex:w.RangeIndex}))));
    return out;
  }
  function recipeTotal(recipe) {
    if (!recipe?.some(r => r.volume != null)) return {total:null,complete:false};
    return {total:Math.round(recipe.reduce((s,r)=>s+(r.volume ?? 0),0)*1e6)/1e6, complete:recipe.every(r=>r.volume !== null)};
  }
  function rectangle(start,end,cols) {
    const list=[]; const r1=Math.floor(start/cols),r2=Math.floor(end/cols),c1=start%cols,c2=end%cols;
    for(let r=Math.min(r1,r2);r<=Math.max(r1,r2);r++) for(let c=Math.min(c1,c2);c<=Math.max(c1,c2);c++) list.push(r*cols+c);
    return list;
  }
  function block(project, start, count=3, direction='horizontal', gap=0, groups=1, groupGap=0) {
    const {Rows:rows,Cols:cols}=project.layout[0];
    if (![start,count,gap,groups,groupGap].every(Number.isInteger) || count<1 || groups<1 || gap<0 || groupGap<0 || start<0 || start>=rows*cols || !['horizontal','vertical'].includes(direction)) throw Error('Use whole numbers for replicate counts and gaps.');
    const out=[];
    for(let g=0;g<groups;g++) { const group=[];
      for(let n=0;n<count;n++) {
        const r=Math.floor(start/cols)+(direction==='vertical'?n*(gap+1):g*(groupGap+1));
        const c=start%cols+(direction==='horizontal'?n*(gap+1):g*(groupGap+1));
        if(r>=rows || c>=cols) throw Error('This block goes beyond the plate. Choose another starting well or fewer replicates.');
        group.push(r*cols+c);
      } out.push(group);
    } return out;
  }
  function ensureEditable(project,indices,layer, allowSameArea=null) {
    const view=cells(project,layer);
    for(const i of indices) {
      if (!Number.isInteger(i) || !view[i]) throw Error('Invalid well selection.');
      if (view[i].locked) throw Error(`${view[i].name} is marked used. Unlock it first if you intend to change it.`);
      if ((view[i].areaIndex!==null && view[i].areaIndex!==allowSameArea) || (view[i].areaIndex===null && view[i].value!==null)) throw Error(`${view[i].name} already contains data. Clear those wells first or choose empty wells.`);
    }
  }
  function condition(project, spec, existing=null) {
    if (!spec.Name?.trim()) throw Error('Give this condition a name.');
    if (project.layout[1].some((a,i)=>a.Name===spec.Name.trim() && i!==existing)) throw Error('A condition with this name already exists. Choose it from the list or use another name.');
    validateRecipe(spec.SetupRecipe || []);
    if(spec.SetupTargetVolume != null && (!Number.isFinite(spec.SetupTargetVolume) || spec.SetupTargetVolume<0)) throw Error('Target volume must be non-negative.');
    if (existing!==null && project.layout[1][existing].Type==='Range') throw Error('Edit ranges in the original editor.');
    const area = existing===null ? {Tags:[],Replicates:3,Direction:'Horizontal',Priority:'Row'} : project.layout[1][existing];
    Object.assign(area,clone(spec),{Name:spec.Name.trim()});
    if(existing===null) {project.layout[1].push(area); return project.layout[1].length-1;} return existing;
  }
  function assign(project,indices,areaIndex,layer=0,value=null,unit='') {
    if(value!==null && (!Number.isFinite(value)||value<0)) throw Error('Concentration must be non-negative.');
    const a=project.layout[1][areaIndex]; if(!a || a.Type==='Range') throw Error('Choose a regular condition. Ranges can be edited in the original editor.');
    ensureEditable(project,indices,layer,areaIndex);
    const unique=[...new Set(indices)];
    project.layout[0].Layers[layer]=project.layout[0].Layers[layer].filter(w=>!unique.includes(w.Index));
    a.Tags.forEach(t=>{if(t.Layer===layer)t.Wells=t.Wells.filter(w=>!unique.includes(w.Index));});
    let tag=a.Tags.find(t=>t.Layer===layer); if(!tag){tag={Layer:layer,Wells:[]};a.Tags.push(tag);}
    unique.forEach(Index=>{const w={Index,RangeIndex:1}; if(value!==null){w.Value=value;w.Unit=unit;project.layout[0].Layers[layer].push(clone(w));}tag.Wells.push(w);});
  }
  function conditionContents(a) {
    const recipe = (a.SetupRecipe || []).map(r => ({
      name: r.name, volume: r.volume, concentration: r.concentration,
      reagentType: r.reagentType ?? 'reagent', amount: r.amount ?? null, amountUnit: r.amountUnit ?? reagentUnits.reagent[0]
    }));
    return {Name:a.Name.trim(),Color:a.Color,Type:a.Type,SetupNotes:a.SetupNotes||'',SetupRecipe:recipe,SetupTargetVolume:a.SetupTargetVolume??null};
  }
  // Applying a draft is scoped to these wells. Only the explicit condition-wide
  // save may change a shared recipe in place while other wells still use it.
  function applyCondition(project,indices,spec,existing=null,layer=0,value=null,unit='') {
    const selected=[...new Set(indices)];
    if(!selected.length)throw Error('Select at least one well first.');
    const next=clone(project),original=existing===null?null:next.layout[1][existing];
    if(existing!==null && !original)throw Error('Choose an existing condition or start a new one.');
    if(original?.Type==='Range')throw Error('Edit ranges in the original editor.');
    if(!spec.Name?.trim())throw Error('Give this condition a name.');
    ensureEditable(next,selected,layer,existing);
    let index;
    if(original && JSON.stringify(conditionContents(original))===JSON.stringify(conditionContents(spec))) {
      index=existing;
    } else if(original && original.Tags.some(t=>t.Wells.some(w=>t.Layer!==layer || !selected.includes(w.Index)))) {
      const base=spec.Name.trim();let name=base,n=1;
      while(next.layout[1].some(a=>a.Name===name)) { name=`${base} (variant${n===1?'':' '+n})`;n++; }
      index=condition(next,{...original,...spec,Name:name,Tags:[]});
      clear(next,selected,layer);
    } else {
      index=condition(next,spec,existing);
    }
    assign(next,selected,index,layer,value,unit);
    validateLayout(next.layout);
    project.layout=next.layout;
    return index;
  }
  function clear(project,indices,layer=0) {
    if(indices.some(i=>project.locked.includes(i))) throw Error('Unlock used wells before clearing them.');
    project.layout[0].Layers[layer]=project.layout[0].Layers[layer].filter(w=>!indices.includes(w.Index));
    project.layout[1].forEach(a=>a.Tags.forEach(t=>{if(t.Layer===layer)t.Wells=t.Wells.filter(w=>!indices.includes(w.Index));}));
  }
  function csv(project) {
    const rows=[['Layer','Well','Condition','Type','Tagged concentration','Unit','Reagent','Volume (µL)','Concentration / note','Total entered (µL)','Recipe volumes complete','Target volume (µL)','Used / locked','Reagent type','Final concentration','Concentration unit','Protein mass per well','Mass unit']];
    project.layout[0].Layers.forEach((_,layer)=>cells(project,layer).forEach(c=>{
      if(!c.area && c.value===null && !c.locked)return;
      const recipe=c.area?.SetupRecipe||[], summary=recipeTotal(recipe);
      (recipe.length?recipe:[{}]).forEach(r=>rows.push([layer+1,c.name,c.area?.Name||'',c.area?.Type||'',c.value??'',c.unit,r.name||'',r.volume??'',r.concentration||'',summary.total??'',summary.complete?'Yes':'No',c.area?.SetupTargetVolume??'',c.locked?'Yes':'No',
        r.reagentType || '', r.reagentType==='reagent' ? r.amount ?? '' : '', r.reagentType==='reagent' && r.amount!=null ? r.amountUnit : '',
        r.reagentType==='protein' ? r.amount ?? '' : '', r.reagentType==='protein' && r.amount!=null ? r.amountUnit : '']));
    }));
    // Prefix text that spreadsheet software could interpret as a formula.
    return '\uFEFF'+rows.map(row=>row.map(v=>'"'+(typeof v==='string'&&/^[\s]*[=+@-]/.test(v)?"'"+v:String(v)).replaceAll('"','""')+'"').join(',')).join('\r\n');
  }
  const api={clone,colors,reagentUnits,id,rowName,wellName,validateLayout,validateRecipe,newProject,importProject,cells,recipeTotal,rectangle,block,ensureEditable,condition,assign,applyCondition,clear,csv};
  if(typeof module!=='undefined' && module.exports)module.exports=api; else root.PlateSetup=api;
})(globalThis);
