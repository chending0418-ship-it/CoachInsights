const fs=require('node:fs'),path=require('node:path');
const deps='/Users/JasonChan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const {chromium}=require(path.join(deps,'playwright'));
const root=path.resolve(__dirname,'../../..'),out=path.join(root,'artifacts/design/ipad-first/review');
const proposals=JSON.parse(fs.readFileSync(path.join(__dirname,'proposal.json')));
const image=file=>'data:image/png;base64,'+fs.readFileSync(file).toString('base64');
(async()=>{const b=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});try{
 for(const s of proposals.schemes){
  const dark=s.id==='studio',companion=s.id==='buddy',screen=s.id==='native'?'board':'video';
  const p=await b.newPage({viewport:{width:1080,height:1440},deviceScaleFactor:1});
  const html=`<html lang="zh-CN"><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;width:1080px;height:1440px;overflow:hidden;background:${dark?'#25191e':companion?'#fff4e4':'#f6f4ef'};color:${dark?'#fff8f0':'#0b1933'};font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;-webkit-font-smoothing:antialiased}
  .wash{position:absolute;left:0;top:0;width:1080px;height:1440px;background:${dark?'radial-gradient(ellipse at 60% 65%,#722f3770,transparent 60%)':companion?'radial-gradient(ellipse at 25% 60%,#e9deca,transparent 65%)':'linear-gradient(160deg,#ffffff80,transparent)'}}
  header{position:absolute;left:78px;top:65px;display:flex;align-items:center;gap:16px}header img{width:58px;height:58px;border-radius:15px}.brand{font:800 27px/1.1 Arial,sans-serif;letter-spacing:-1.215px}.brand span{font-weight:400}.brand small{display:block;font:400 14px/1.4 -apple-system,sans-serif;letter-spacing:2px;margin-top:8px}.english{position:absolute;right:80px;top:87px;font:13px Arial,sans-serif;letter-spacing:2px;opacity:.6}
  .eyebrow{position:absolute;left:83px;top:211px;font-size:15px;letter-spacing:4px;color:${dark?'#d3a5ae':'#89515a'}}
  h1{position:absolute;left:78px;top:245px;font-size:${companion?'84px':'88px'};font-weight:600;letter-spacing:-3px;line-height:1.28;margin:0}
  .desc{position:absolute;left:83px;top:490px;width:860px;font-size:23px;line-height:1.65;opacity:.7;margin:0}
  .tablet{position:absolute;left:${dark?'72px':'80px'};top:${dark?'590px':'600px'};width:${dark?'900px':'920px'};border:${companion?'10px':'15px'} solid ${companion?'#d9d0c4':'#1e2023'};border-radius:${companion?'36px':'32px'};overflow:hidden;background:#1e2023;box-shadow:0 32px 75px ${dark?'#0007':'#26322920'};transform:${dark?'rotate(-3deg)':companion?'rotate(2deg)':'none'}}
  .tablet img{width:100%;display:block}.line{position:absolute;left:82px;right:82px;bottom:130px;height:1px;background:currentColor;opacity:.15}
  footer{position:absolute;left:82px;right:82px;bottom:64px;display:flex;justify-content:space-between;align-items:center;font-size:16px;opacity:.7}.note{position:absolute;left:82px;bottom:162px;font-size:13px;opacity:.5}
  </style><div class="wash"></div><header><img src="${image(path.join(__dirname,'assets/app-icon.png'))}"><div class="brand">Baseball<span>Master.cc</span><small>棒球训练助手</small></div></header><div class="english">DRILL BUDDY</div><div class="eyebrow">${s.id==='native'?'PRACTICE WORTH KEEPING':dark?'A CLOSER LOOK':'BETTER PRACTICE TOGETHER'}</div><h1>${s.headline.replace('\n','<br>')}</h1><p class="desc">${s.supporting}</p><div class="tablet"><img src="${image(path.join(out,s.id+'-'+screen+'.png'))}"></div><p class="note">UI 概念稿 · 视频画面为 AI 示例素材 · 非正式 App 截图</p><div class="line"></div><footer><span>${s.name} / 宣传方向示意</span><span>BASEBALLMASTER</span></footer></html>`;
  await p.setContent(html);await p.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode()));});
  const issues=await p.evaluate(()=>[...document.querySelectorAll('header,h1,.desc,.tablet,footer')].map(e=>({x:e.getBoundingClientRect().x,right:e.getBoundingClientRect().right,bottom:e.getBoundingClientRect().bottom})).filter(r=>r.x<0||r.right>1080||r.bottom>1440));
  if(issues.length)throw Error(JSON.stringify(issues));await p.screenshot({path:path.join(out,s.id+'-brand-direction.png')});await p.close();
 }
 console.log('Rendered 3 brand-direction applications using the actual concept screens.');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
