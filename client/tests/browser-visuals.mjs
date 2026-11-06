import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';
const {chromium}=createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root=process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/visuals/', import.meta.url));
const url=process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
await fs.mkdir(root,{recursive:true});
const browser=await chromium.launch({executablePath:process.env.CAS_BROWSER_PATH,headless:true});
try {
const page=await browser.newPage({viewport:{width:1360,height:768}});
const reports=[];
const errors=[];
page.on('pageerror',e=>errors.push(e.stack));
const q=(op,params={})=>page.evaluate(async request=>(await import(performance.getEntriesByType('resource').filter(e=>e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request),{op,...params});
const btn=label=>page.getByRole('button',{name:label,exact:true});
const wait=ms=>page.waitForTimeout(ms);
const pausedStep=async()=>{await btn('推进一秒').click();await wait(55);return q('observe');};
async function loadedPortrait(surface, characterId, name) {
  const card=surface.locator(`.ship-portrait[data-character="${characterId}"]`);
  await card.waitFor();
  const art=card.getByAltText(`${name}舰娘立绘`,{exact:true});
  await art.evaluate(el=>el.decode());
  assert(await art.evaluate(el=>el.naturalWidth>0&&el.naturalHeight>0));
  assert.match(await card.locator('figcaption').innerText(),/舰型代表/);
}
await page.goto(url);
await signInLocal(page,'cas-visual-qa',true);
await resumeExercise(page);
const initial=await q('observe');
const chosen=initial.ships[0];
assert(chosen.gunRange>0&&chosen.torpedoRange>0);
const rangeText=await page.locator('.range-legend').textContent();
assert(rangeText.includes((chosen.gunRange/1000).toFixed(1)+' km'));
assert(rangeText.includes((chosen.torpedoRange/1000).toFixed(1)+' km'));
const ringBefore=await page.locator('.battle-map > canvas').first().evaluate(el=>el.toDataURL());
await btn('显示所选舰射程').click();
assert.equal(await page.locator('.range-legend').count(),0);
const ringAfter=await page.locator('.battle-map > canvas').first().evaluate(el=>el.toDataURL());
assert.notEqual(ringAfter,ringBefore);
await btn('显示所选舰射程').click();
await btn('舰况').click();
assert.equal(chosen.classId,'fletcher');
await loadedPortrait(page,'IBS-U-USN-FLETCHER','弗莱彻');
assert.equal(await page.locator('.mount-icon').count(),chosen.systems.guns.length+chosen.systems.tubes.length);
assert.match(await page.locator('.hull-meter').textContent(),new RegExp(String(chosen.hp)));
await page.getByRole('combobox',{name:'查看舰艇'}).selectOption(String(initial.ships.find(s=>s.kind==='cl').id));
await loadedPortrait(page,'IBS-U-USN-UNNAMED-T01-R26','克利夫兰');
assert.equal(await page.locator('.range-legend .torpedo-ring').count(),0);
await page.getByRole('combobox',{name:'查看舰艇'}).selectOption(String(chosen.id));
await page.screenshot({path:root+'/01-ship-ranges.png'});
reports.push({realRanges:rangeText,ringToggledCanvas:true,realSchematicMounts:await page.locator('.mount-icon').count(),cruiserNoTorpedoRing:true});
async function pos(x,y) {
  const b=await page.locator('.battle-map').boundingBox();
  const s=Math.min((b.width-65)/24000,(b.height-42)/14000);
  return {x:b.x+(b.width-24000*s)/2+x*s,y:b.y+(b.height+14000*s)/2-y*s};
}
async function center(loc) {const b=await loc.boundingBox();return {x:b.x+b.width/2,y:b.y+b.height/2};}
async function dragStart(loc, point) {const at=await center(loc);await page.mouse.move(at.x,at.y);await page.mouse.down();await page.mouse.move(point.x,point.y,{steps:20});}
const gun=page.locator('[data-ship="1"] .gun');
const target=initial.contacts.find(c=>c.id==='C01');
await dragStart(gun,await pos(target.x,target.y));
await page.waitForFunction(()=>document.querySelector('.gesture-tip')?.textContent.includes('门炮可用'));
await page.locator('[data-ship="1"] .tactical-turret.trained').first().waitFor();
assert.equal(await page.locator('[data-contact] .tactical-turret').count(),0);
assert(initial.contacts.every(c=>!('systems' in c)&&!('classId' in c)));
await page.screenshot({path:root+'/09-trained-turret.png'});
await page.mouse.up();
await page.getByRole('status').filter({hasText:'已下达炮击'}).waitFor();
await q('step',{seconds:179});
const launch=await pausedStep();
assert(launch.shells.some(s=>s.own),'No shell flight entities at launch');
const first=launch.shells.find(s=>s.own);
assert.equal(first.impactTick-first.launchTick,8);
assert(launch.ships.some(ship=>ship.systems.guns.some(mount=>typeof mount.bearing==='number')));
await q('step',{seconds:3});
const flight=await pausedStep();
const middle=flight.shells.find(s=>s.id===first.id);
assert(middle&&middle.progress>=0.5&&middle.progress<1&&middle.x!==first.x);
const delta=await page.locator('.projectile-layer').evaluate(el=>{
  const data=el.getContext('2d').getImageData(0,0,el.width,el.height).data;
  let visible=0;
  for(let i=3;i<data.length;i+=4) if(data[i]>0) visible++;
  return visible;
});
assert(delta>15,'Expected nonempty projectile canvas');
await page.screenshot({path:root+'/02-shell-flight.png'});
reports.push({projectileTime:flight.tick,progress:middle.progress,projectilePixels:delta,ownTurretsTrained:true,contactsWithoutMounts:true});
await q('step',{seconds:3});
let impact=await pausedStep();
assert(!impact.shells.some(s=>s.id===first.id));
if(!impact.events.some(e=>['damage','critical','hit','torpedo_hit','sunk'].includes(e.kind))){
  for(let i=0;i<50;i++) {
    const found=await q('step',{seconds:16});
    if(found.events.some(e=>found.tick-e.tick<9&&['damage','critical','hit','torpedo_hit','sunk'].includes(e.kind)))break;
  }
  impact=await pausedStep();
}
await page.locator('.battle-alert').first().waitFor();
const ids=await page.locator('.battle-alert').evaluateAll(nodes=>nodes.map(node=>node.dataset.eventId));
assert.equal(new Set(ids).size,ids.length);
const eventIds=new Set(impact.events.map(e=>String(e.id)));
assert(ids.every(id=>eventIds.has(id)));
await page.screenshot({path:root+'/03-impact-alert.png'});
const selectedGun=page.locator('.weapon.gun').first();
assert(await selectedGun.count(), 'Expected a gun badge to test gesture safety');
{
  const p=await center(selectedGun);await page.mouse.move(p.x,p.y);await page.mouse.down();
  await page.locator('.cancel-well.visible').waitFor();
  assert.equal(await page.locator('.battle-alerts').evaluate(el=>getComputedStyle(el).visibility),'hidden');
  const b=await center(page.locator('.cancel-well'));await page.mouse.move(b.x,b.y,{steps:9});await page.mouse.up();
  assert.equal(await page.locator('.battle-alerts').evaluate(el=>getComputedStyle(el).visibility),'visible');
}
const noDuplicates=await page.locator('.battle-alert').evaluateAll(nodes=>nodes.map(node=>node.dataset.eventId));
assert.equal(new Set(noDuplicates).size,noDuplicates.length);
reports.push({realAlertIds:ids,gestureSafeAlerts:true});

await btn('演习设置').click();
await page.getByLabel('所属方').selectOption('axis');
await btn('开始新演习').click();
await page.getByRole('dialog').waitFor({state:'hidden'});
await btn('舰况').click();
await loadedPortrait(page,'IBS-U-IJN-KAGERO','阳炎');
const sendai=(await q('observe')).ships.find(ship=>ship.classId==='sendai');
await page.getByRole('combobox',{name:'查看舰艇'}).selectOption(String(sendai.id));
await loadedPortrait(page,'IBS-U-IJN-SENDAI','川内');
await page.screenshot({path:root+'/08-sendai-portrait.png'});
reports.push({portraits:['IBS-U-USN-FLETCHER','IBS-U-USN-UNNAMED-T01-R26','IBS-U-IJN-KAGERO','IBS-U-IJN-SENDAI'],matchedBy:'classId'});
await btn('战术 AI').click();
await page.getByLabel('AI 风格').selectOption('torpedo');
await page.getByLabel('指挥权限').selectOption('auto');
assert.equal((await q('observe')).fleets[0].ai.mode,'auto');
let detected;
for(let i=0;i<160;i++) {
  const state=await q('step',{seconds:16});
  detected=state.torpedoes.find(t=>t.own&&t.from&&Math.hypot(t.x-t.from.x,t.y-t.from.y)>200);
  if(detected||state.result) break;
}
assert(detected,'No visible own torpedo wake in the exercise');
const wake=await pausedStep();
const moved=wake.torpedoes.find(t=>t.id===detected.id);
assert(moved && Math.hypot(moved.x-detected.x,moved.y-detected.y)>1);
assert.deepEqual(moved.from,detected.from);
const layer=page.locator('.projectile-layer');
await layer.screenshot({path:root+'/05a-torpedo-overlay.png'});
await page.screenshot({path:root+'/05-torpedo-wake.png'});
await btn('1×').click();
await btn('开始演习').click();
const format=tick=>String(Math.floor(tick/60)).padStart(2,'0')+':'+String(tick%60).padStart(2,'0');
let tween;
for(let i=1;i<=3&&!tween;i++){
  const nextTime=format(wake.tick+i);
  await page.waitForFunction(time=>document.querySelector('.time strong')?.textContent===time,nextTime);
  const a=await layer.evaluate(el=>el.toDataURL());
  await wait(220);
  const b=await layer.evaluate(el=>el.toDataURL());
  if(a!==b && await page.locator('.time strong').textContent()===nextTime) tween=true;
}
assert(tween,'Projectile canvas did not animate between displayed clock updates');
await btn('暂停演习').click();
reports.push({realTorpedo:moved.id,origin:moved.from,previous:{x:detected.x,y:detected.y},current:{x:moved.x,y:moved.y},interpolatedFrames:true});

await btn('母港').click();
await page.locator('.growth-campaign-entry').click();
await page.locator('.archive-list').waitFor();
assert.equal(await page.locator('.archive-list > li').count(),16);
assert.equal(await page.getByText('未开放',{exact:true}).count(),16);
await page.getByLabel('档案范围').selectOption('exact_historical_counterpart');
assert.equal(await page.locator('.archive-list > li').count(),11);
await page.locator('.archive-list summary').filter({hasText:'圣乔治角海战'}).click();
assert.match(await page.locator('.archive-list details[open] .archive-detail').innerText(),/Rising Sun.*PDF/s);
await page.locator('.archive-list details[open] .archive-source').waitFor();
await page.screenshot({path:root+'/06-campaign-archive.png'});
const sourceCount=await page.locator('.archive-list summary').count();
for(let i=0;i<sourceCount;i++){
  const row=page.locator('.archive-list > li').nth(i);
  if(!await row.locator('details').evaluate(node=>node.open)) await row.locator('summary').click();
  await row.locator('.archive-source').waitFor();
  assert.equal(await row.locator('.archive-sides section').count(),2);
}
await btn('开始夜航演习').click();
await page.locator('.night-exercise').waitFor();
const night=await q('observe');
assert.equal(night.variant,'night');
assert.equal(night.ships.length,5);
assert.equal(night.contacts.length,0);
await page.screenshot({path:root+'/07-night-exercise.png'});
reports.push({archiveCount:16,historicalMatches:11,historicalDetailsRendered:sourceCount,playableHistorical:0,nightInitialContacts:night.contacts.length});
await btn('演习设置').click();
await page.getByLabel('演习时段').selectOption('radar');
await page.getByLabel('所属方').selectOption('allies');
await btn('开始新演习').click();
await page.getByText('虚构夜间演习 · 雷达回波 R',{exact:true}).waitFor();
const radar=await q('observe');
assert.equal(radar.variant,'radar');
assert(radar.radarContacts.length>0);
assert(radar.radarContacts.every(c=>c.name===undefined&&c.heading===undefined&&c.speed===undefined));
assert.equal(await page.locator('[data-contact^=R]').count(),radar.radarContacts.length);
await btn('舰况').click();
const radarToggle=page.getByRole('button',{name:/^SG,.* · 开启$/});
await radarToggle.click();
await page.getByRole('button',{name:/^SG,.* · 关闭$/}).waitFor();
const switched=await q('observe');
assert.equal(switched.ships[0].systems.radars.find(r=>r.id==='us_sg').powered,false);
await page.screenshot({path:root+'/08-radar-exercise.png'});
reports.push({radarEchoes:radar.radarContacts.length,privateContactFieldsOmitted:true,radarSwitchConfirmed:true});
await btn('母港').click();
await page.locator('.growth-port').waitFor();
await page.locator('.growth-officer > img').evaluate(img=>img.decode());
await page.screenshot({path:root+'/00-original-mother-port.png'});
const phone=await browser.newPage({viewport:{width:740,height:360},hasTouch:true,isMobile:true});
phone.on('pageerror',e=>errors.push(e.stack));
await phone.goto(url);
await signInLocal(phone,'cas-visual-mobile-qa',true);
await resumeExercise(phone);
await phone.getByRole('button',{name:'舰况',exact:true}).tap();
assert(await phone.locator('.schematic-plate').isVisible());
await loadedPortrait(phone,'IBS-U-USN-FLETCHER','弗莱彻');
await phone.screenshot({path:root+'/04-phone-status.png'});
assert.deepEqual(errors,[]);
await fs.writeFile(root+'/browser-visual-receipt.json',JSON.stringify(reports,null,2));
console.log(JSON.stringify(reports,null,2));
} finally { await browser.close(); }
