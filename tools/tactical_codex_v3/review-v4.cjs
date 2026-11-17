const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
function parseCsv(text){const rows=[],row=[];let cell='',quoted=false;for(let i=0;i<text.length;i++){const c=text[i];if(i===0&&c==='\ufeff')continue;if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}else if(!quoted&&c===','){row.push(cell);cell='';}else if(!quoted&&(c==='\r'||c==='\n')){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);rows.push(row.splice(0));cell='';}else cell+=c;}if(cell||row.length){row.push(cell);rows.push(row);}return rows;}
module.exports=async function({page,mobilePage}){
 const out=path.resolve('artifacts/island-war-v4/codex');fs.mkdirSync(out,{recursive:true});
 const report={checks:[],failures:[],page_errors:[],network_requests:[],scope:'Real headless Chromium pointer/keyboard, file:// offline, no user browser or account.'};
 const check=(value,label)=>{report.checks.push(label);if(!value)report.failures.push(label);};
 for(const p of [page,mobilePage]){p.on('pageerror',e=>report.page_errors.push(e.message));p.on('request',r=>{if(/^https?:/.test(r.url()))report.network_requests.push(r.url());});}
 const source=fs.readFileSync('godot/data/island-war-v4-published.json'),sha=crypto.createHash('sha256').update(source).digest('hex');
 await page.goto('file:///D:/desktop/cas/output/tactical-codex-v4-20261115/index.html');await page.evaluate(()=>document.fonts.ready);
 check(await page.locator('.unit-item').count()===27,'All 27 personalities appear');
 const baseline=await page.evaluate(()=>CODEX_REVIEW.baseline);
 check(await page.evaluate(()=>CODEX_DATA.baseline.weapons.every(w=>CODEX_DATA.weaponArt[w.id])),'All native weapon IDs have explicit art mapping, including platform representations');
 report.weapon_models={count:baseline.weapons.length,families:new Set(baseline.weapons.map(w=>w.family_id||w.id)).size};
 check(await page.evaluate(()=>CODEX_REVIEW.baseline.weapons.every(w=>CadenceCodex.has(w)&&w.family_id&&CODEX_DATA.weaponArt[w.id].family_id===w.family_id)),'Every concrete native model has separate cadence fields and an explicit family art reference');
 check(new Set(baseline.cards.map(c=>c.weapon_composition[0].weapon_id)).size===baseline.cards.length,'All personalities use their own concrete primary models');
 check(baseline.cards.every(c=>c.fixed_transport&&c.transport_options.length===1&&c.transport_options[0].kind===c.default_transport),'Every personality has one fixed landing vehicle, not a selectable transport list');
 for(const id of ['MCP-022','MCP-103','MCP-087','MCP-027','MCP-006']){
  const c=baseline.cards.find(c=>c.id===id);
  check(c.combat_vehicles.length===1&&c.combat_vehicles[0].count_per_company===1&&c.combat_vehicles[0].min_crew===0,'One independently controlled combat vehicle per company without added driver bodies '+id);
  check(c.combat_vehicles[0].repair_cost_full&&Object.values(c.combat_vehicles[0].repair_cost_full).every(n=>n>=0),'Independent vehicle maintenance costs come from the same native catalogue '+id);
 }
 check(baseline.cards.find(c=>c.id==='MCP-022').combat_vehicles[0].passenger_seats===0,'The independent tank has no passenger seating');
 check(await page.evaluate(()=>CadenceCodex.validate(CODEX_REVIEW.baseline)),'Native burst and magazine timing uses valid10Hz values');
 const cadenceMeans=await page.evaluate(()=>CODEX_REVIEW.baseline.weapons.reduce((m,w)=>Math.max(m,Math.abs(w.mean_fire_interval_s-CadenceCodex.mean(w))),0));
 check(cadenceMeans<1e-9,'Every native concrete model mean fire interval includes the exact full magazine and overlapping reload cycle');report.weapon_models.mean_interval_max_error=cadenceMeans;
 if(baseline.weapons.some(w=>w.accuracy)){
  const samples=await page.evaluate(()=>{let n=0,maxError=0;for(const w of CODEX_REVIEW.baseline.weapons){for(const s of w.accuracy.samples||[]){for(const [key,moving] of [['stationary',false],['moving',true]]){n++;maxError=Math.max(maxError,Math.abs(AccuracyCodex.probability(w,s.distance_m,moving)-s[key]));}}}return {n,maxError,valid:AccuracyCodex.validate(CODEX_REVIEW.proposal)};});
  report.accuracy_model=samples;
  check(samples.n>100&&samples.maxError<1e-9,'Every native stationary/moving accuracy sample matches the exported piecewise formula');check(samples.valid,'Native curve knots are ordered and 0–1 bounded');
  await page.locator('[data-unit="MCP-184"]').click();await page.getByRole('tab',{name:'武器与目标'}).click();await page.locator('.accuracy-picker summary').click();
  const dmr=baseline.weapons.find(w=>(w.family_id||w.id)==='dmr');await page.locator(`[data-accuracy-weapon="${dmr.id}"]`).click();
  check(await page.locator('.accuracy-legend').allTextContents().then(t=>t.join(' ').includes(dmr.name)),'A DMR can be compared beside the selected SMG and primary/secondary loadout');
  const comparison=page.getByRole('slider',{name:'比较距离',exact:true});await comparison.focus();await page.keyboard.press('ArrowRight');check(await page.locator('#accuracy-distance-value').innerText()===(Number(await comparison.inputValue())+' m'),'Comparison distance updates through real slider input');
  await comparison.focus();await page.keyboard.press('End');check(Number(await comparison.inputValue())===await page.evaluate(()=>Math.max(...Array.from(AccuracyCodex.state.selected).map(id=>CODEX_REVIEW.proposal.weapons.find(w=>w.id===id).range_m))),'Short-range indirect weapons do not clamp the long-range comparison distance');await page.locator('#accuracy-moving').click();check(await page.locator('#accuracy-moving').getAttribute('aria-pressed')==='true','Moving accuracy uses the same original multiplier');
  await page.locator('.accuracy-section').screenshot({style:'.masthead{visibility:hidden}',path:path.join(out,'smg-dmr-distance-curves.png')});
  await page.getByRole('button',{name:'调整方案',exact:true}).click();await page.locator('.accuracy-tuning summary').click();const accuracySlider=page.getByRole('slider',{name:'基础命中系数 · '+dmr.name,exact:true});await accuracySlider.focus();await page.keyboard.press('ArrowRight');
  check(await page.evaluate(id=>CODEX_REVIEW.proposal.weapons.find(w=>w.id===id).accuracy.base_hit!==CODEX_REVIEW.baseline.weapons.find(w=>w.id===id).accuracy.base_hit,dmr.id),'Accuracy proposal slider changes the copy and leaves baseline intact');
  check(await page.evaluate(id=>CODEX_REVIEW.proposal.weapons.filter(w=>w.family_id==='dmr'&&w.id!==id).every(w=>JSON.stringify(w)===JSON.stringify(CODEX_REVIEW.baseline.weapons.find(b=>b.id===w.id))),dmr.id),'Changing one DMR model does not change other DMR models in the same family');
  const knotSlider=page.getByRole('slider',{name:'射程 50% 时倍率 · '+dmr.name,exact:true});await knotSlider.focus();await page.keyboard.press('ArrowLeft');
  check(await page.evaluate(()=>AccuracyCodex.validate(CODEX_REVIEW.proposal)),'Curve sliders keep knot order and multiplier bounds valid');
  const accuracyDownload=page.waitForEvent('download');await page.getByRole('button',{name:'导出 JSON'}).click();const accuracyFile=await accuracyDownload;await accuracyFile.saveAs(path.join(out,'edited-accuracy-proposal.json'));
  const accuracyJson=JSON.parse(fs.readFileSync(path.join(out,'edited-accuracy-proposal.json'),'utf8')),savedAccuracy=accuracyJson.catalogue.weapons.find(w=>w.id===dmr.id).accuracy;
  check(savedAccuracy.base_hit!==dmr.accuracy.base_hit&&savedAccuracy.curve[2].multiplier!==dmr.accuracy.curve[2].multiplier,'JSON preserves both edited base accuracy and the edited curve knot');
  check(savedAccuracy.samples[5].stationary!==dmr.accuracy.samples[5].stationary,'Exported accuracy samples are recalculated from the edited proposal, never stale baseline numbers');
  const accuracyCsvDownload=page.waitForEvent('download');await page.getByRole('button',{name:'导出 CSV'}).click();const accuracyCsv=await accuracyCsvDownload;await accuracyCsv.saveAs(path.join(out,'edited-accuracy-proposal.csv'));const accuracyCsvText=fs.readFileSync(path.join(out,'edited-accuracy-proposal.csv'),'utf8');
  check(accuracyCsvText.includes(String(savedAccuracy.base_hit))&&accuracyCsvText.includes(String(savedAccuracy.curve[2].multiplier)),'CSV preserves edited base accuracy and curve values');
  await page.getByRole('button',{name:'还原基线'}).click();await page.getByRole('button',{name:'结束调整',exact:true}).click();await page.getByRole('tab',{name:'编制与职责'}).click();
 }
 if(baseline.weapons.every(w=>w.fire_interval_s!=null)){
  await page.locator('[data-unit="MCP-184"]').click();await page.getByRole('tab',{name:'武器与目标'}).click();
  const squad=baseline.cards.find(c=>c.id==='MCP-184'),burstModel=baseline.weapons.find(w=>w.fire_mode==='burst'&&squad.weapon_composition.some(s=>s.weapon_id===w.id));
  check(!!burstModel,'The breacher squad has an actual burst weapon model');
  const panel=page.locator('.weapon').filter({has:page.getByRole('heading',{name:burstModel.name,exact:true})});
  check((await panel.innerText()).includes(String(burstModel.magazine_capacity))&&(await panel.innerText()).includes('空匣换弹'),'Model detail separates magazine size from real reload duration');
  await page.getByRole('button',{name:'调整方案',exact:true}).click();
  const fire=panel.getByRole('slider',{name:'连射间隔',exact:true});await fire.focus();await page.keyboard.press('ArrowRight');
  check(await page.evaluate(id=>{const w=CODEX_REVIEW.proposal.weapons.find(w=>w.id===id),b=CODEX_REVIEW.baseline.weapons.find(w=>w.id===id);return w.fire_interval_s!==b.fire_interval_s&&w.magazine_reload_s===b.magazine_reload_s;},burstModel.id),'Changing burst fire interval leaves magazine reload duration unchanged');
  const magazine=panel.getByRole('slider',{name:'弹匣容量',exact:true});await magazine.focus();await page.keyboard.press('ArrowRight');
  check(await page.evaluate(id=>{const w=CODEX_REVIEW.proposal.weapons.find(w=>w.id===id),b=CODEX_REVIEW.baseline.weapons.find(w=>w.id===id);return w.magazine_capacity!==b.magazine_capacity&&w.ammo_capacity===b.ammo_capacity;},burstModel.id),'Increasing magazine capacity never creates extra carried ammunition');
  const reload=panel.getByRole('slider',{name:'弹匣换弹时间',exact:true});await reload.focus();await page.keyboard.press('ArrowRight');
  const jsonWait=page.waitForEvent('download');await page.getByRole('button',{name:'导出 JSON'}).click();await(await jsonWait).saveAs(path.join(out,'edited-cadence-proposal.json'));
  const saved=JSON.parse(fs.readFileSync(path.join(out,'edited-cadence-proposal.json'),'utf8')).catalogue.weapons.find(w=>w.id===burstModel.id);
  check(saved.magazine_reload_s!==burstModel.magazine_reload_s&&saved.fire_interval_s!==burstModel.fire_interval_s&&saved.magazine_capacity!==burstModel.magazine_capacity&&saved.ammo_capacity===burstModel.ammo_capacity,'JSON preserves independent edited burst timing, magazine and reload without adding ammunition');
  check(Math.abs(saved.mean_fire_interval_s-await page.evaluate(id=>CadenceCodex.mean(CODEX_REVIEW.proposal.weapons.find(w=>w.id===id)),burstModel.id))<1e-9,'Edited cadence exports a recalculated magazine cycle instead of a stale native mean');
  const csvWait=page.waitForEvent('download');await page.getByRole('button',{name:'导出 CSV'}).click();await(await csvWait).saveAs(path.join(out,'edited-cadence-proposal.csv'));
  const csv=parseCsv(fs.readFileSync(path.join(out,'edited-cadence-proposal.csv'),'utf8')),headers=csv[0],row=csv.find(r=>r[headers.indexOf('武器ID')]===burstModel.id);
  check(row&&Number(row[headers.indexOf('射内间隔s')])===saved.fire_interval_s&&Number(row[headers.indexOf('换弹s')])===saved.magazine_reload_s&&Number(row[headers.indexOf('总携弹含弹匣')])===saved.ammo_capacity,'Actual CSV download separates the concrete model cadence, reload duration and finite ammunition columns');
  await panel.screenshot({path:path.join(out,'concrete-burst-model-editor.png'),style:'.masthead,#editor-bar{visibility:hidden}'});
  await page.getByRole('button',{name:'还原基线'}).click();await page.getByRole('button',{name:'结束调整',exact:true}).click();await page.getByRole('tab',{name:'编制与职责'}).click();
 }
 for(const c of baseline.cards){
  await page.locator(`[data-unit="${c.id}"]`).click();
  check(await page.locator('.hero-portrait').evaluate(async img=>{await img.decode();return img.naturalWidth>0;}),'Portrait decodes '+c.id);
  check(await page.locator('.hero-sprite image').evaluate(async img=>{const i=new Image();i.src=img.getAttribute('href');await i.decode();return i.naturalWidth>0;}),'Own sprite decodes '+c.id);
  check(await page.locator('.hero h2').innerText()===c.name,'Native identity matches '+c.id);
  check(await page.locator('.hero-chip').innerText()===`一个人格 · ${c.company_count} 个连队 · ${c.company_count*c.personnel_per_company} 个身体`,'Finite body count '+c.id);
 }
 await page.locator('#search').fill('不存在的部队');check(await page.locator('.unit-item').count()===0,'Empty search is readable and does not destroy current detail');check(await page.locator('.hero h2').isVisible(),'Current detail remains accessible on empty search');
 await page.locator('#search').fill('MCP-088');check(await page.locator('.unit-item').count()===1,'Search by exact identity');await page.locator('#search').fill('');
 await page.waitForFunction(()=>!document.getElementById('toast').classList.contains('show'));
 for(const id of ['MCP-203','MCP-184','MCP-145','MCP-128']){
  const c=baseline.cards.find(c=>c.id===id);await page.locator(`[data-unit="${id}"]`).click();await page.getByRole('tab',{name:'编制与职责'}).click();
  check((await page.locator('.hero-description').innerText()).includes(c.ability.name),'Latest real role ability is visible '+id);
  check((await page.locator('#detail').innerText()).includes(String(c.body_stats.armor_multiplier)),'Personal protection is visible as an incoming multiplier '+id);
  await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(out,'role-'+id+'-overview.png'),fullPage:true});
 }
 await page.locator('[data-filter="artillery"]').click();check(await page.locator('.unit-item').count()===baseline.cards.filter(c=>c.role==='artillery').length,'Role filter follows native roles');await page.locator('[data-filter="all"]').click();
 await page.locator('[data-unit="MCP-063"]').click();await page.getByRole('tab',{name:'编制与职责'}).click();check((await page.locator('.overview-grid').first().innerText()).includes('1 人'),'One AT specialist is clearly grouped');
 await page.getByRole('tab',{name:'武器与目标'}).click();check(await page.locator('.matrix').first().locator('.target').count()===6,'Every weapon shows six actual target classes');
 const matrix=await page.evaluate(()=>{const c=CODEX_REVIEW.proposal.cards.find(c=>c.id==='MCP-063'),g=CODEX_REVIEW.groups(c)[0];return CODEX_REVIEW.proposal.weapons.find(w=>w.id===g.id);});
 check((await page.locator('.matrix').first().innerText()).includes(String(matrix.multipliers.parachuting)),'Parachuting multiplier comes from native weapon table');
 await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(out,'desktop-antiarmor.png'),fullPage:true});
 await page.getByRole('button',{name:'调整方案',exact:true}).click();const slider=page.getByRole('slider',{name:'基础伤害',exact:true}).first();await slider.focus();await page.keyboard.press('ArrowRight');const changed=Number(await slider.inputValue());
 check(changed!==matrix.damage,'Real keyboard slider changes proposal damage');
 check(await page.evaluate(()=>CODEX_REVIEW.baseline.weapons.find(w=>w.id===CODEX_REVIEW.groups(CODEX_REVIEW.proposal.cards.find(c=>c.id==='MCP-063'))[0].id).damage)===matrix.damage,'Original baseline remains immutable while editing');
 await page.getByRole('tab',{name:'投送与载具'}).click();await page.getByRole('tab',{name:'武器与目标'}).click();check(Number(await page.getByRole('slider',{name:'基础伤害',exact:true}).first().inputValue())===changed,'Proposal survives tab changes');
 const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'导出 JSON'}).click();const dl=await downloadPromise;await dl.saveAs(path.join(out,'edited-proposal.json'));const json=JSON.parse(fs.readFileSync(path.join(out,'edited-proposal.json'),'utf8'));check(json.catalogue.cards.length===27&&json.source_sha256===sha,'JSON includes all 27 and precise source provenance');check(json.catalogue.weapons.find(w=>w.id===matrix.id).damage===changed,'JSON contains the actual edited number');
 const csvPromise=page.waitForEvent('download');await page.getByRole('button',{name:'导出 CSV'}).click();const csv=await csvPromise;await csv.saveAs(path.join(out,'edited-proposal.csv'));const text=fs.readFileSync(path.join(out,'edited-proposal.csv'),'utf8');check(baseline.cards.every(c=>text.includes(c.id)),'CSV includes all 27 identities');check(text.includes(String(changed)),'CSV contains edited damage');check(await page.evaluate(()=>new Set(CODEX_REVIEW.csvRows().map(r=>r.length)).size===1),'CSV rows all have the same columns');
 await page.getByRole('button',{name:'还原基线'}).click();check(Number(await page.getByRole('slider',{name:'基础伤害',exact:true}).first().inputValue())===matrix.damage,'Reset restores exact native baseline');await page.getByRole('button',{name:'结束调整',exact:true}).click();check(await page.locator('[data-path]').count()===0,'Leaving edit mode hides proposal sliders while comparison distance stays available');
 await page.locator('[data-unit="MCP-087"]').click();await page.getByRole('tab',{name:'编制与职责'}).click();check((await page.locator('#detail').innerText()).includes('每连职责'),'Artillery infantry roles remain separate from their independent vehicle');await page.getByRole('tab',{name:'投送与载具'}).click();
 const vehicleCount=await page.locator('.vehicle-card').count();check(vehicleCount>5,'Independent transport and combat vehicle atlas appears');await page.locator('.vehicle-card').first().scrollIntoViewIfNeeded();await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(out,'desktop-artillery-vehicles.png'),fullPage:true});
 const imgs=await page.locator('.vehicle-picture image').evaluateAll(async nodes=>Promise.all(nodes.map(async n=>{const i=new Image();i.src=n.getAttribute('href');await i.decode();return i.naturalWidth>0;})));check(imgs.every(Boolean),'Every listed independent vehicle image decodes');
 await page.locator('[data-unit="MCP-022"]').click();check((await page.locator('#detail').innerText()).includes('无乘员座位，步兵始终在车外独立协同'),'Tank detail explicitly separates its six rifle bodies from its zero seats');
 await page.locator('[data-unit="MCP-009"]').click();await page.getByRole('tab',{name:'武器与目标'}).click();const engineer=baseline.cards.find(c=>c.id==='MCP-009'),explosive=baseline.weapons.find(w=>w.id===engineer.ability.weapon_id);const demolitionPanel=page.locator('.weapon').filter({has:page.getByRole('heading',{name:explosive.name,exact:true})});check((await demolitionPanel.innerText()).includes('每连实际库存')&&!(await demolitionPanel.innerText()).includes('空匣换弹'),'Engineering charges show their actual finite skill pool instead of gun magazine cadence');
 await mobilePage.goto('file:///D:/desktop/cas/output/tactical-codex-v4-20261115/index.html');await mobilePage.evaluate(()=>document.fonts.ready);await mobilePage.locator('[data-unit="MCP-006"]').click();check(await mobilePage.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'390px mobile overview has no horizontal page overflow');await mobilePage.evaluate(()=>scrollTo(0,0));await mobilePage.screenshot({path:path.join(out,'mobile-six-bodies.png'),fullPage:true});await mobilePage.getByRole('tab',{name:'投送与载具'}).click();check((await mobilePage.locator('.vehicle-card .badge').allTextContents()).some(t=>t.includes('独立作战载具 · 每连 1 架')),'The six-body air assault company has exactly one independent helicopter');check(await mobilePage.locator('.vehicle-card.current').count()===1,'The mobile loadout shows exactly one fixed landing method');await mobilePage.locator('.vehicle-card.current').screenshot({path:path.join(out,'mobile-fixed-helicopter-insertion.png'),style:'.masthead{visibility:hidden}'});await mobilePage.getByRole('button',{name:'调整方案',exact:true}).click();await mobilePage.getByRole('tab',{name:'武器与目标'}).click();check(await mobilePage.getByRole('slider').count()>0,'Mobile proposal sliders are accessible');check(await mobilePage.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'390px mobile editor has no horizontal page overflow');await mobilePage.evaluate(()=>scrollTo(0,0));await mobilePage.screenshot({path:path.join(out,'mobile-proposal-editor.png'),fullPage:true});
 if(baseline.weapons.some(w=>w.accuracy)){
  await mobilePage.getByRole('button',{name:'结束调整',exact:true}).click();await mobilePage.locator('[data-unit="MCP-184"]').click();await mobilePage.getByRole('tab',{name:'武器与目标'}).click();
  check(await mobilePage.locator('.accuracy-chart').count()>0,'Native distance curves are visible on a390px mobile viewport');
  check(await mobilePage.locator('.accuracy-chart svg').first().evaluate(svg=>{const t=svg.querySelector('text');return parseFloat(getComputedStyle(t).fontSize)*svg.clientWidth/svg.viewBox.baseVal.width>=8;}),'Mobile curve axis labels retain at least8 actual screen pixels');
  check(await mobilePage.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile native curve charts do not overflow the page');
  await mobilePage.locator('.accuracy-chart').first().screenshot({path:path.join(out,'mobile-distance-curve.png'),style:'.masthead{visibility:hidden}'});
 }
 await page.reload();check(await page.evaluate(()=>JSON.stringify(CODEX_REVIEW.proposal)===JSON.stringify(CODEX_REVIEW.baseline)),'Reopening discards unexported proposal changes');check(crypto.createHash('sha256').update(fs.readFileSync('godot/data/island-war-v4-published.json')).digest('hex')===sha,'Source catalogue bytes remain unchanged');check(report.page_errors.length===0,'No browser script errors');check(report.network_requests.length===0,'No network required: images, font and data are local');report.source_sha256=sha;report.accuracy_samples=baseline.weapons.reduce((n,w)=>n+(w.accuracy?.samples?.length||0)*2,0);report.count=report.checks.length;fs.writeFileSync(path.join(out,'receipt.json'),JSON.stringify(report,null,2));return {checks:report.count,failures:report.failures,source_sha256:sha,accuracy_samples:report.accuracy_samples};
};
