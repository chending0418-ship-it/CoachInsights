const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const deps='/Users/JasonChan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {chromium}=require(path.join(deps,'playwright'));
const here=__dirname,root=path.resolve(here,'../../..'),out=path.join(root,'artifacts/design/ipad-first/review');
const preview=path.join(out,'preview.html');
(async()=>{
 fs.mkdirSync(out,{recursive:true});
 const b=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try{
  const page=await b.newPage({viewport:{width:1226,height:1100},deviceScaleFactor:2});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/lucide@*/dist/umd/lucide.js',r=>r.fulfill({path:path.join(deps,'lucide/dist/umd/lucide.js'),contentType:'text/javascript'}));
  await page.goto('file://'+preview,{waitUntil:'load'});
  const frame=page.frames().find(x=>x.parentFrame());await frame.waitForFunction(()=>typeof lucide!=='undefined');
  await frame.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode())));
  const screens=[];
  for(const key of ['native','studio','buddy']){
   const app=frame.locator(`[data-world="${key}"]`);
   for(const screen of ['home','board','video']){
    await app.locator('[data-action="home"]').first().click();
    if(screen!=='home')await app.locator(`[data-action="${screen}"]`).first().click();
    if(key==='buddy'&&screen==='board')await app.locator('[data-action="b-step"]').click();
    const measured=await app.evaluate(el=>({width:el.clientWidth,height:el.clientHeight,overflow:el.scrollWidth-el.clientWidth}));
    assert.ok(measured.overflow<=2,JSON.stringify(measured));
    const file=`${key}-${screen}.png`;await app.screenshot({path:path.join(out,file)});
    screens.push({design:key,screen,file,...measured});
   }
   await app.locator('[data-action="home"]').first().click();
   await app.locator('[data-action="board"]').first().click();
   const player=app.locator('[data-interactive-field] [data-player="游"]');
   await player.scrollIntoViewIfNeeded();const before=await player.getAttribute('transform'),box=await player.boundingBox();
   await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2+22,box.y+box.height/2+10,{steps:8});await page.mouse.up();
   assert.notEqual(await player.getAttribute('transform'),before);
   if(key==='buddy')await app.locator('[data-action="b-step"]').click();else await app.locator('[data-action="draw"]').click();
   const field=await app.locator('[data-interactive-field]').boundingBox();
   await page.mouse.move(field.x+field.width*.45,field.y+field.height*.5);await page.mouse.down();await page.mouse.move(field.x+field.width*.6,field.y+field.height*.35,{steps:8});await page.mouse.up();
   assert.equal(await app.locator('[data-strokes] path').count(),1);await app.locator('[data-action="undo"]').click();assert.equal(await app.locator('[data-strokes] path').count(),0);
   await app.locator('[data-action="home"]').first().click();await app.locator('[data-action="video"]').first().click();await app.locator('[data-action="next"]').click();
   await frame.waitForFunction(k=>document.querySelector(`[data-world="${k}"] [data-setting="timeline"]`).value==='49',key);
   if(key==='buddy'){await app.locator('[data-action="b-step"]').click();await app.locator('[data-action="finish"]').click();assert.equal(await app.locator('.buddy-finish').count(),1);}
   await app.locator('[data-action="home"]').first().click();
  }
  let layoutChecks=0;
  for(const width of [1398,1056,800,422,352]){
   await page.setViewportSize({width,height:1100});
   for(const key of ['native','studio','buddy']){
    const app=frame.locator(`[data-world="${key}"]`);
    for(const screen of ['home','board','video']){
     await app.locator('[data-action="home"]').first().click();
     if(screen!=='home')await app.locator(`[data-action="${screen}"]`).first().click();
     assert.ok(await app.evaluate(el=>el.scrollWidth-el.clientWidth)<=2,`${key} ${screen} ${width}`);layoutChecks++;
    }
    await app.locator('[data-action="home"]').first().click();
   }
  }
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(out,'prototype-checks.json'),JSON.stringify({date:'2026-11-05',screenCount:9,screens,layoutChecks,inputWidths:[1366,1024,768,390,320],flows:['navigation','player drag','drawing','undo','frame step','guided completion'],pageErrors:errors,passed:true,nativeAppVerified:false},null,2)+'\n');
  // Independent overview boards make every design visible without a carousel.
  const names={native:'原生资料库',studio:'专业工作室',buddy:'轻松陪练'};
  const sections=['home','board','video'],labels=['首页','战术白板','视频分析'];
  const data=file=>'data:image/png;base64,'+fs.readFileSync(path.join(out,file)).toString('base64');
  for(const key of ['native','studio','buddy']){
   const board=await b.newPage({viewport:{width:2400,height:760},deviceScaleFactor:1});
   await board.setContent(`<html><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;padding:38px 40px;background:${key==='studio'?'#22262a':'#f1eee7'};color:${key==='studio'?'#f4eee8':'#0b1933'};font-family:-apple-system,sans-serif}h1{font-size:30px;margin:0 0 7px;font-weight:600}p{font-size:14px;opacity:.65;margin:0 0 23px}.screens{display:grid;grid-template-columns:repeat(3,1fr);gap:24px}.screens img{width:100%;display:block;box-shadow:0 12px 25px #0002;border-radius:12px}.screens h2{font-size:17px;margin:14px 0 0;font-weight:500}</style><h1>${names[key]}</h1><p>Drill Buddy 棒球训练助手 / iPad 首发设计提案 / 2026-11-05</p><div class="screens">${sections.map((s,n)=>`<div><img src="${data(key+'-'+s+'.png')}"><h2>${labels[n]}</h2></div>`).join('')}</div></html>`);
   await board.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode())));
   await board.screenshot({path:path.join(out,key+'-overview.png'),fullPage:true});await board.close();
  }
  console.log(`PASS: 9 retina screens, ${layoutChecks} layout checks, drag/draw/undo/frame flows and guided completion; 3 overview boards.`);
 }finally{await b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
