// Offline QA only: render generated sprites at large and actual 80px display sizes.
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const require=createRequire(process.env.CAS_PLAYWRIGHT_PACKAGE || 'C:/Users/fwj/AppData/Local/OpenAI/Codex/runtimes/cua_node/76f5b5935a63c7ba/bin/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const root=fileURLToPath(new URL('../',import.meta.url));
const catalog=JSON.parse(readFileSync(root+'godot/data/ships.json','utf8'));
const ids=['IBS-U-USN-FLETCHER','IBS-U-USN-PERKINS','IBS-U-USN-MAURY','IBS-U-USN-DRAYTON','IBS-U-USN-HONOLULU','IBS-U-IJN-KAGERO'];
const cards=ids.map(id=>catalog.ships.find(s=>s.id===id));
const cells=cards.map(s=>{
const data='data:image/png;base64,'+readFileSync(root+'godot/'+s.chibi_generated.replace('res://','')).toString('base64');
return `<section><h2>${s.name}</h2><div class="large"><img src="${data}"></div><div class="small sea"><img src="${data}"><span>80 px</span></div><div class="small light"><img src="${data}"><span>80 px</span></div></section>`;
}).join('');
const html=`<!doctype html><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;padding:24px;background:#20252c;color:#eaf0f4;font:16px 'Microsoft YaHei'}h1{font-size:25px;margin:0 0 8px}p{color:#aebbc5;margin:0 0 24px}main{display:grid;grid-template-columns:repeat(6,1fr);gap:12px}section{background:#2c343e;border:1px solid #46515e}h2{font-size:19px;margin:14px;text-align:center}.large{height:235px;display:grid;place-items:center}.large img{height:225px;max-width:100%;object-fit:contain}.small{height:102px;margin:10px;display:flex;align-items:center;justify-content:center;gap:12px}.small img{height:80px;max-width:110px;object-fit:contain}.small span{font-size:13px}.sea{background:#102d3c}.light{background:#f0f3f5;color:#263746}</style><h1>CAS 原创 SD 首批候选</h1><p>按 CAS 原立绘保留角色特征；候选稿，尚未标记用户验收。下方为实际 80px 显示检查。</p><main>${cells}</main>`;
mkdirSync(root+'artifacts/godot',{recursive:true});
writeFileSync(root+'artifacts/godot/chibi-first-wave-review.html',html);
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const page=await browser.newPage({viewport:{width:1440,height:650},deviceScaleFactor:1});
await page.setContent(html);await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
await page.screenshot({path:root+'artifacts/godot/chibi-first-wave-review.png'});
await browser.close();console.log(root+'artifacts/godot/chibi-first-wave-review.png');
