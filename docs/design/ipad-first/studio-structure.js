// Overrides for the professional shell; keeps the confirmed three-scene catalog.
 const scenes={
 personal:{name:'私教',sub:'观察动作，留下反馈',hint:'教练讲解、家长陪练与个人回看',icon:'viewfinder',tools:[
 ['P01','视频分析','慢放、逐帧与画面标注','clapperboard','video'],['P02','动作对比','两段视频，同步观察','columns-2','available'],['P03','个人训练计划','编写个人训练安排','clipboard-list','pending'],['P04','教练笔记','记录观察与教学重点','notebook-pen','pending'],['P05','课后练习卡','填写并分享课后练习','send','pending']]},
 team:{name:'团训',sub:'安排训练，现场记录',hint:'组织一场训练，快速记录场上情况',icon:'users',tools:[
 ['T01','训练计划','安排项目、顺序与时长','clipboard-list','pending'],['T02','按计划计时','跟随训练项目分段计时','timer','pending'],['T03','打击记录','滚地、高飞等简单计数','pencil-line','pending'],['T04','投球记录','牛棚好坏球、出局与总球数','crosshair','pending'],['T05','比赛计数器','当前好坏球与出局数','hash','pending']]},
 quick:{name:'随手工具',sub:'计时、画战术、测距离',hint:'打开即用的场边工具',icon:'wrench',tools:[
 ['Q01','秒表','开始、暂停、分段计时','timer','available'],['Q02','倒计时','设定时长，即刻开始','alarm-clock','available'],['Q03','战术白板','摆放球员，画下路线','pen-tool','board'],['Q04','测距','AR 实景距离估算','ruler','available']]}
 };
 function studioRail(s){const selected=s.scene||'personal';return `<nav class="studio-rail" aria-label="功能模块"><small class="rail-section">功能模块</small>${Object.entries(scenes).map(([key,v])=>btn('scene-'+key,v.name,v.icon,s.page!=='records'&&selected===key?'active':'')).join('')}<div class="rail-bottom"><small class="rail-section">公共入口</small>${btn('records','全部记录','folder',s.page==='records'?'active':'')}${btn('s-settings','设置','settings-2')}</div></nav>`;}
 function studioHome(){const s=state.studio,scene=scenes[s.scene||'personal'];return `<main class="studio-page"><div class="studio-title"><div><div class="eyebrow">DRILL BUDDY / 工具箱</div><h1 style="margin-top:12px">${scene.name}</h1><small>${scene.sub}。${scene.hint}。</small></div><span class="module-count">${scene.tools.length} 项工具</span></div><div class="module-tools">${scene.tools.map(([code,name,desc,icon,mode])=>`<button class="module-tool cursor-interaction ${mode==='pending'?'pending':''}" data-action="tool-${code}"><div class="row between"><span class="module-symbol">${i(icon)}</span><small>${code}</small></div><h2>${name}</h2><p>${desc}</p><div class="row between"><small>${mode==='pending'?'内容待完善':code==='Q04'?'已接入 · 真机精度待验收':'已有功能'}</small>${i('arrow-up-right')}</div></button>`).join('')}</div><div class="studio-strip"><span>${scene.name}的记录</span>${btn('records','查看记录','arrow-right')}</div><div class="module-record">${s.scene==='quick'?btn('tool-Q03','内野防守站位　 ·　 白板草稿示例','pen-tool'):s.scene==='team'?'<span class="muted">团训工具内容完善后，在这里继续查看训练记录。</span>':btn('tool-P01','打击练习　 ·　 视频分析示例','clapperboard')}</div>${notice()}</main>`;}
 const originalRender=render;
 render=function(app){
  const s=state[app.dataset.world];
  if(app.dataset.world==='studio'&&!s.scene)s.scene='personal';
  originalRender(app);
  if(app.dataset.world!=='studio')return;
  app.classList.toggle('tool-open',!['home','records'].includes(s.page));
  const top=app.querySelector('.studio-header .row');
  top.innerHTML=`<small>iPad 优先 / iPhone 保留</small>${btn('home','工具箱','layout-grid')}`;
  const context=app.querySelector('.studio-context');
  if(context)context.insertAdjacentHTML('beforebegin',`<div class="module-crumb">${btn('scene-'+s.scene,scenes[s.scene].name,'chevron-left')}<span>／ ${s.page==='board'?'战术白板':'视频分析'}</span></div>`);
  if(s.page==='records')app.querySelector('.studio-page').innerHTML=`<div class="studio-title"><div><div class="eyebrow">LIBRARY / 公共入口</div><h1 style="margin-top:12px">全部记录</h1><small>按私教、团训、随手工具及具体工具筛选。</small></div></div><div class="records-filter">${Object.entries(scenes).map(([k,v])=>btn('recordfilter-'+k,v.name,'',s.recordScene===k?'active':'')).join('')}</div><div class="module-record">${s.recordScene==='team'?'<p>团训记录待对应工具接入。</p>':s.recordScene==='quick'?btn('tool-Q03','内野防守站位　 ·　 随手工具 / 战术白板','pen-tool'):btn('tool-P01','打击练习　 ·　 私教 / 视频分析','clapperboard')}</div>${notice()}`;
  if(s.page==='pending'){
   const t=scenes[s.scene].tools.find(t=>t[0]===s.tool);
   app.querySelector('.studio-page').innerHTML=`<div class="module-crumb">${btn('scene-'+s.scene,scenes[s.scene].name,'chevron-left')}</div><div class="pending-detail"><span class="module-symbol">${i(t[3])}</span><h1>${t[1]}</h1><p>${t[2]}</p><small>${t[4]==='pending'?'入口保留，内容待完善。':'已有原生功能，本次先评审功能结构与入口。'}</small></div>${notice()}`;
  }
  if(typeof lucide!=='undefined')lucide.createIcons({attrs:{width:18,height:18}});
 };
 root.addEventListener('click',e=>{
  const app=e.target.closest('[data-world="studio"]'),b=e.target.closest('[data-action]');if(!app||!b)return;
  const a=b.dataset.action,s=state.studio;
  if(a.startsWith('scene-')){s.scene=a.slice(6);s.page='home';}
  else if(a.startsWith('tool-')){s.tool=a.slice(5);s.scene=Object.keys(scenes).find(k=>scenes[k].tools.some(t=>t[0]===s.tool));const t=scenes[s.scene].tools.find(t=>t[0]===s.tool);s.page=t[4]==='board'?'board':t[4]==='video'?'video':'pending';}
  else if(a==='records'){s.page='records';s.recordScene=s.scene;}
  else if(a.startsWith('recordfilter-')){s.recordScene=a.slice(13);}
  else return;
  e.stopImmediatePropagation();clearInterval(s.timer);s.playing=false;s.mode='move';render(app);
  window.openai?.setWidgetState?.({modelContent:{scene:scenes[s.scene].name,page:s.page,iPhoneSupported:true},privateContent:{scene:s.scene,page:s.page}})?.catch(()=>{});
 },true);
