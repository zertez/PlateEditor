// Open an analysis copy in upstream PlateEditor without a .save download/upload.
window.addEventListener('load', () => {
  const bar=document.createElement('div');
  bar.style.cssText='padding:12px;background:#edf4ed;border-bottom:1px solid #ccd9cf;font:14px system-ui;margin-bottom:12px';
  const link=document.createElement('a');link.href='index.html';link.textContent='← Back to Plate Setup';bar.append(link);
  if(new URLSearchParams(location.search).has('setup')){
    try{const text=sessionStorage.getItem('plate-setup.handoff');if(text){const data=JSON.parse(text);Editor.loadData(data[0],data[1]);bar.append(document.createTextNode(' · Analysis copy. Layout changes here do not update your saved plate or ingredient recipes.'));}}
    catch(e){bar.append(document.createTextNode(' · Could not load the plate: '+e.message));}
  }
  document.body.prepend(bar);
});
