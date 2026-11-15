/* Presentation preferences are independent of experimental plate data. */
(function (root) {
  'use strict';
  const M = typeof module !== 'undefined' && module.exports ? require('./model.js') : root.PlateSetup;
  const fields = {
    name: 'Full condition name',
    type: 'Condition type',
    tagged: 'Tagged concentration',
    ingredients: 'Reagent names',
    concentrations: 'Reagent concentrations / notes',
    volumes: 'Reagent volumes',
    totals: 'Total and target volume',
    notes: 'Condition notes'
  };
  const defaults = {version:2, mode:'overview', width:240, font:13, wide:false, crop:false, print:'details', fields:Object.fromEntries(Object.keys(fields).map(k=>[k,true]))};
  const escape = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const number = n => Number(n).toLocaleString(undefined,{maximumFractionDigits:6});
  function normalize(input = {}) {
    if (!input || typeof input !== 'object') input = {};
    const inRange = (value, min, max, fallback) => typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max ? value : fallback;
    return {
      version:2,
      mode:['overview','contents','details'].includes(input.mode)?input.mode:defaults.mode,
      width:inRange(input.width,140,360,defaults.width),
      font:inRange(input.font,10,18,defaults.font),
      wide:input.wide === true,
      crop:input.crop === true,
      print:input.print === 'plate'?'plate':'details',
      fields:Object.fromEntries(Object.keys(fields).map(k=>[k,typeof input.fields?.[k]==='boolean'?input.fields[k]:true]))
    };
  }
  function preset(mode, current = {}) {
    const next=normalize(current);next.mode=mode;
    if(mode==='details') {next.fields={...defaults.fields};next.width=240;next.font=13;}
    if(mode==='contents') {next.fields={...defaults.fields,type:false,tagged:false,notes:false};next.width=200;next.font=12;}
    return normalize(next);
  }
  function bounds(cells, plate, crop) {
    let firstRow=0,lastRow=plate.Rows-1,firstCol=0,lastCol=plate.Cols-1;
    const assigned=cells.filter(c=>c.area||c.value!==null||c.locked);
    if(crop && assigned.length) {
      const rows=assigned.map(c=>Math.floor(c.index/plate.Cols)),cols=assigned.map(c=>c.index%plate.Cols);
      firstRow=Math.min(...rows);lastRow=Math.max(...rows);firstCol=Math.min(...cols);lastCol=Math.max(...cols);
    }
    return {firstRow,lastRow,firstCol,lastCol};
  }
  function restore(input) {
    const next=normalize(input);
    // Reset the earlier oversized display once; retain subsequent explicit choices.
    if(input?.version!==defaults.version){next.mode='overview';next.wide=false;next.crop=false;}
    return next;
  }
  function wellContent(c, options) {
    const o=normalize(options),f=o.fields,a=c.area,recipe=a?.SetupRecipe||[];
    if(o.mode==='overview') return `<span class="well-code">${a?c.areaIndex+1:escape(c.name)}${c.locked?' · used':''}</span>${c.value!==null?`<span class="well-dose">${escape(number(c.value)+' '+c.unit)}</span>`:''}`;
    const output=[`<span class="well-heading"><strong>${escape(c.name)}</strong>${a?`<span>Condition ${c.areaIndex+1}</span>`:''}${c.locked?'<span class="used-label">Used / locked</span>':''}</span>`];
    if(!a && c.value===null) output.push('<span class="well-placeholder">Unassigned</span>');
    if(a && f.name) output.push(`<span class="well-title">${escape(a.Name).split(' | ').map(s=>`<span>${s}</span>`).join('')}</span>`);
    if(a && f.type) output.push(`<span class="well-field"><span class="field-label">Type</span>${escape(a.Type||'Not recorded')}${a.Type==='Range'?` · #${escape(c.rangeIndex??1)}`:''}</span>`);
    if(f.tagged && c.value!==null) output.push(`<span class="well-field"><span class="field-label">Tagged concentration</span><strong>${escape(number(c.value)+' '+c.unit)}</strong></span>`);
    // Names remain visible with volumes or concentrations to keep those values identifiable.
    if(a && (f.ingredients||f.volumes||f.concentrations)) {
      output.push(`<span class="well-ingredients"><span class="field-label">Contents per well</span>${recipe.length?recipe.map(r=>`<span class="reagent-entry"><span class="reagent-top"><span>${escape(r.name)}</span>${f.volumes?`<strong>${r.volume===null?'Not recorded':number(r.volume)+' µL'}</strong>`:''}</span>${f.concentrations&&r.concentration?`<span class="reagent-note">${escape(r.concentration)}</span>`:''}</span>`).join(''):'<span class="well-placeholder">Recipe not recorded</span>'}</span>`);
    }
    if(a && f.totals) {
      const t=M.recipeTotal(recipe);
      if(t.total!==null) output.push(`<span class="well-total"><span>${t.complete?'Total per well':'Volume entered'}</span><strong>${number(t.total)} µL</strong>${t.complete?'':'<span class="incomplete">Some volumes are not recorded</span>'}</span>`);
      if(a.SetupTargetVolume!=null) output.push(`<span class="well-field"><span class="field-label">Target volume</span>${number(a.SetupTargetVolume)} µL</span>`);
    }
    if(a && f.notes && a.SetupNotes) output.push(`<span class="well-field well-notes"><span class="field-label">Notes</span>${escape(a.SetupNotes)}</span>`);
    return output.join('');
  }
  function printSections(project, layer, options) {
    const o=normalize(options),plate=project.layout[0],cells=M.cells(project,layer),b=bounds(cells,plate,o.crop),out=[];
    for(let first=b.firstCol;first<=b.lastCol;first+=4){
      const last=Math.min(first+3,b.lastCol),columns=Array.from({length:last-first+1},(_,i)=>first+i);
      const header=`${escape(project.title)} · Layer ${layer+1} · Columns ${first+1}–${last+1}`;
      let rows='';
      for(let r=b.firstRow;r<=b.lastRow;r++)rows+=`<tr><th scope="row">${M.rowName(r)}</th>${columns.map(col=>{const c=cells[r*plate.Cols+col];return `<td class="print-well" style="--well-color:${/^#[0-9a-f]{6}$/i.test(c.area?.Color)?c.area.Color:'#ffffff'}">${wellContent(c,{...o,mode:'details'})}</td>`;}).join('')}</tr>`;
      out.push(`<section class="print-section"><table><thead><tr><th colspan="${columns.length+1}" class="print-title">${header}</th></tr><tr><th></th>${columns.map(c=>`<th scope="col">${c+1}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table></section>`);
    }
    return out.join('');
  }
  function printWhole(project, layer, options) {
    const o=normalize(options),plate=project.layout[0],cells=M.cells(project,layer),b=bounds(cells,plate,o.crop);
    let html='<span></span>';
    for(let col=b.firstCol;col<=b.lastCol;col++)html+=`<span class="print-axis">${col+1}</span>`;
    for(let row=b.firstRow;row<=b.lastRow;row++){
      html+=`<span class="print-axis">${M.rowName(row)}</span>`;
      for(let col=b.firstCol;col<=b.lastCol;col++){
        const c=cells[row*plate.Cols+col];
        html+=`<div class="print-export-well" style="--well-color:${/^#[0-9a-f]{6}$/i.test(c.area?.Color)?c.area.Color:'#ffffff'}">${wellContent(c,{...o,mode:'details'})}</div>`;
      }
    }
    return `<header class="print-whole-title"><h2>${escape(project.title)}</h2><p>Layer ${layer+1} · ${M.wellName(b.firstRow*plate.Cols+b.firstCol,plate.Cols)}–${M.wellName(b.lastRow*plate.Cols+b.lastCol,plate.Cols)} · Volumes in µL; unrecorded volumes remain unknown.</p></header><div id="print-whole-frame"><div id="print-whole-grid" style="--cols:${b.lastCol-b.firstCol+1}">${html}</div></div>`;
  }
  const api={fields,defaults,normalize,preset,bounds,restore,wellContent,printSections,printWhole};
  if(typeof module!=='undefined' && module.exports)module.exports=api;else root.PlateSetupDisplay=api;
})(globalThis);
