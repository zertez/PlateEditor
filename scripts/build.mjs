// Dependency-free development build of the original editor.
import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
async function walk(dir) { const entries=await readdir(dir,{withFileTypes:true});const files=[];for(const e of entries){const p=join(dir,e.name);files.push(...(e.isDirectory()?await walk(p):[p]));}return files.sort(); }
await mkdir('dist',{recursive:true});
for(const app of ['ui','shared','editor','analyzer','grapher']){
 const files=await walk('src/'+app),js=[],css=[];
 for(const f of files){if(f.endsWith('.js'))js.push({f,text:await readFile(f,'utf8')});if(f.endsWith('.css'))css.push(await readFile(f,'utf8'));}
 // Base classes must be evaluated before subclasses. The original Gulp order is filesystem-dependent.
 const pending=[...js],ordered=[],defined=new Set();
 while(pending.length){const index=pending.findIndex(x=>{const match=x.text.match(/class\s+\w+\s+extends\s+(\w+)/);return !match||defined.has(match[1]);});if(index<0)throw Error('Unresolved class dependency in '+app);const [x]=pending.splice(index,1);ordered.push(x.text);for(const m of x.text.matchAll(/class\s+(\w+)/g))defined.add(m[1]);}
 await writeFile(`dist/${app}.min.js`,ordered.join('\n;\n'));await writeFile(`dist/${app}-styles.css`,css.join('\n'));
}
console.log('Built original editor assets. Open index.html for Plate Setup.');
