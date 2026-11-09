"""Render the source-backed iPad design proposal; all output stays in artifacts/."""
from pathlib import Path
import json, hashlib, re
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'artifacts/design/ipad-first/review'
DATA=json.loads((HERE/'proposal.json').read_text())
OUT.mkdir(parents=True,exist_ok=True)
W,H=landscape(A3)
M=56
NAVY='#0B1933'; WINE='#722F37'; INK='#161b22'; SUB='#626d78'; LINE='#d9d9d9'
for name,file in [('CN','/System/Library/Fonts/STHeiti Light.ttc'),('CNB','/System/Library/Fonts/STHeiti Medium.ttc'),('AR','/System/Library/Fonts/Supplemental/Arial.ttf'),('ARB','/System/Library/Fonts/Supplemental/Arial Bold.ttf')]:
    pdfmetrics.registerFont(TTFont(name,file,subfontIndex=0))
TARGET=OUT/'Drill-Buddy-iPad-design-review.pdf'
c=canvas.Canvas(str(TARGET),pagesize=(W,H),pageCompression=1)
c.setTitle(DATA['title']);c.setAuthor('BaseballMaster');c.setSubject('Three distinct iPad UI UX directions and implementation assessment')
page=0; elements=[]; checks=[]

def col(value):return HexColor(value)
def wrapped(text,width,size,font):
    lines=[]
    for para in str(text).split('\n'):
        local=[];line=''
        tokens=re.findall(r'[A-Za-z][A-Za-z0-9_./:\-]*|\s+|.',para)
        for token in tokens:
            pieces=list(token) if pdfmetrics.stringWidth(token,font,size)>width else [token]
            for piece in pieces:
                if line and pdfmetrics.stringWidth(line+piece,font,size)>width:
                    if piece in '，。；：！？）》】、,.!?;:%':
                        match=re.search(r'[A-Za-z][A-Za-z0-9_]*$',line)
                        tail=match.group(0) if match else line[-1:]
                        local.append(line[:-len(tail)].rstrip());line=tail+piece
                    elif line[-1:] in '（《【“‘':
                        local.append(line[:-1].rstrip());line=line[-1]+piece.lstrip()
                    else:
                        local.append(line.rstrip());line=piece.lstrip()
                else:line+=piece
        if len(line)<=2 and local and len(local[-1])>6 and all(ord(ch)>127 for ch in local[-1][-3:]):
            line=local[-1][-3:]+line;local[-1]=local[-1][:-3]
        local.append(line);lines.extend(local)
    return lines
def text(value,x,top,width,size=14,font='CN',ink=INK,leading=None):
    lead=leading or size*1.6;lines=wrapped(value,width,size,font)
    height=len(lines)*lead
    assert x>=0 and x+width<=W+1 and top>=0 and top+height<=H-43,(page,str(value)[:35],top,height)
    for n,line in enumerate(lines):
        for ch in line:
            if ord(ch)>127:assert ord(ch) in pdfmetrics.getFont(font).face.charToGlyph,('missing glyph',ch)
        c.setFillColor(col(ink));c.setFont(font,size);c.drawString(x,H-top-size-n*lead,line)
    elements.append({'kind':'text','x':x,'top':top,'width':width,'height':height,'text':str(value)})
    return top+height
def rule(x,top,width):
    c.setStrokeColor(col(LINE));c.setLineWidth(.7);c.line(x,H-top,x+width,H-top)
def image(file,x,top,width,max_height=None):
    file=Path(file);iw,ih=Image.open(file).size;height=width*ih/iw
    if max_height and height>max_height:height=max_height;width=height*iw/ih
    assert top+height<=H-43,(file,top,height)
    c.drawImage(str(file),x,H-top-height,width,height,mask='auto')
    elements.append({'kind':'image','x':x,'top':top,'width':width,'height':height,'file':str(file)})
    return width,height
def start(title,section,subtitle=''):
    global page,elements
    if page:finish()
    page+=1;elements=[]
    c.setFillColor(col('#fffefa'));c.rect(0,0,W,H,fill=1,stroke=0)
    text('BASEBALLMASTER  /  DRILL BUDDY',M,27,600,size=10,font='AR',ink=SUB)
    text(section,W-330,27,270,size=10,ink=SUB)
    text(title,M,66,W-2*M,size=28,font='CNB',ink='#000000',leading=35)
    if subtitle:text(subtitle,M,109,W-2*M,size=12,ink=SUB,leading=19)
    c.bookmarkPage('p'+str(page));c.addOutlineEntry(title,'p'+str(page),level=0)
def finish():
    rule(M,H-36,W-2*M)
    c.setFont('AR',9);c.setFillColor(col(SUB));c.drawString(M,20,'DESIGN REVIEW  |  2026-11-05  |  CONCEPTS, NOT RELEASED APP SCREENS')
    c.drawRightString(W-M,20,str(page).zfill(2))
    checks.append({'page':page,'elements':elements});c.showPage()
def paragraph(title,body,x,top,width,size=14):
    y=text(title,x,top,width,size=17,font='CNB',ink='#000000',leading=25)
    return text(body,x,y+9,width,size=size,leading=size*1.65)+22
def table(headers,rows,x,top,widths,row_h=64):
    head_h=40;total=sum(widths)
    c.setFillColor(col(NAVY));c.rect(x,H-top-head_h,total,head_h,fill=1,stroke=0)
    xx=x
    for header,w in zip(headers,widths):text(header,xx+12,top+10,w-24,size=13,font='CNB',ink='#ffffff',leading=19);xx+=w
    yy=top+head_h
    for r,row in enumerate(rows):
        c.setFillColor(col('#ffffff' if r%2==0 else '#f3f5f7'));c.rect(x,H-yy-row_h,total,row_h,fill=1,stroke=0)
        xx=x
        for value,w in zip(row,widths):
            lines=wrapped(value,w-24,12.5,'CN');h=len(lines)*19
            assert h<=row_h-12,(r,value)
            text(value,xx+12,yy+(row_h-h)/2,w-24,size=12.5,leading=19);xx+=w
        yy+=row_h
    c.setStrokeColor(col(LINE));c.setLineWidth(.65)
    xx=x
    for w in [0]+widths:
        xx+=w;c.line(xx,H-top,xx,H-yy)
    for y in [top,top+head_h]+[top+head_h+(n+1)*row_h for n in range(len(rows))]:c.line(x,H-y,x+total,H-y)
    return yy

# Cover
start(DATA['title'],'产品体验与品牌方向')
text(DATA['subtitle'],M,127,W-2*M,size=23,ink=NAVY)
text(DATA['status'],M,171,W-2*M,size=13,ink=SUB)
text(DATA['conclusion'],M,224,W-2*M,size=18,leading=31)
cw=(W-2*M-36)/3
for n,s in enumerate(DATA['schemes']):
    x=M+n*(cw+18)
    image(OUT/(s['id']+'-home.png'),x,405,cw,max_height=257)
    text(s['name'],x,682,cw,size=18,font='CNB')
    text(s['position'],x,717,cw,size=13,ink=SUB)
text('每套包含首页 战术白板 视频分析三张效果图  另附可交互原型与实现边界',M,769,W-2*M,size=12,ink=SUB)

start('先确定产品的中心','共同设计前提','三套方案共享现有功能基础 差异发生在信息架构 操作方式和传播重心')
cw=(W-2*M-62)/2
for n,p in enumerate(DATA['principles']):
    x=M+(n%2)*(cw+62);y=165+(n//2)*265
    text(str(n+1).zfill(2),x,y,cw,size=12,font='AR',ink=WINE)
    paragraph(p['title'],p['body'],x,y+29,cw,size=16)

start('三套方案改变的是什么','方案比较','不是同一套卡片的换色 每套都有自己的导航对象和编辑节奏')
rows=[
 ['体验中心','本机内容与记录','当前项目与画布','眼前的一项练习任务'],
 ['首页结构','缩略图资料库与最近编辑','项目预览与工作区轨道','任务入口与继续上次练习'],
 ['白板操作','固定工具栏与检查器','画布边缘浮层与对象托盘','站位与路线分步引导'],
 ['视频操作','文档式编辑与可见控制','时间码与缩略图工作区','先选帧 再标要点'],
 ['品牌感受','安静 可信赖 易于接近','克制 专注 专业工具','温暖 清楚 陪伴式沟通'],
 ['主要代价','需要处理好空库与内容增长','学习成本及户外深色可读性','熟练用户需要快速跳过引导'],
 ['首发适配','最贴近现有本机资料结构','复用核心 增加编辑器外壳','复用核心 增加引导状态层']]
table(['比较项','原生资料库','专业工作室','轻松陪练'],rows,M,159,[150,300,300,W-2*M-750],row_h=69)
text('以上为设计判断 不代表用户测试结果 开发工期估算或真实性能测量',M,731,W-2*M,size=12,ink=SUB)

for s in DATA['schemes']:
    start(s['name'],s['english'],s['position'])
    left=500;right_x=650;right_w=W-M-right_x
    text(s['headline'],M,168,left,size=40,font='CNB',ink=NAVY,leading=57)
    y=paragraph('主要使用者',s['audience'],M,325,left,size=15)
    y=paragraph('操作顺序',s['architecture'],M,y+5,left,size=16)
    paragraph('选择这套的理由',s['strength'],M,y+7,left,size=15)
    y=paragraph('界面与操作',s['visual']+'\n'+s['ux'],right_x,165,right_w,size=14)
    y=paragraph('对应的宣传调性',s['marketing'],right_x,y+4,right_w,size=14)
    paragraph('文案边界',s['avoid'],right_x,y+4,right_w,size=13)
    rule(M,724,W-2*M)
    text('需要接受的取舍',M,741,180,size=13,font='CNB')
    text(s['tradeoff'],M+190,737,W-2*M-190,size=13,leading=21)
    for shot in s['screens']:
        start(s['name']+' '+shot['title'],s['english'],shot['intent'])
        image(OUT/(s['id']+'-'+shot['key']+'.png'),M,157,840,max_height=597)
        x=930;width=W-M-x;y=164
        for n,note in enumerate(shot['notes']):
            text(str(n+1).zfill(2),x,y,width,size=11,font='ARB',ink=WINE)
            y=text(note,x,y+24,width,size=13,leading=21)+26
        y=text('落地注意',x,y+1,width,size=14,font='CNB',leading=22)+9
        text(shot['behavior'],x,y,width,size=12,leading=19)

start('落地时复用什么 改动什么','实现方案','实现评估来自当前开发分支 不是对全新分析算法或服务的承诺')
table(['模块','改动性质','实现边界'],DATA['implementation'],M,159,[145,185,W-2*M-330],row_h=66)
text('这些是工作范围而非日程承诺 选定方向后再拆分实施任务和原生验收',M,751,W-2*M,size=12,ink=SUB)

start('把 iPad 首发做成真实闭环','适配与验证','效果图和浏览器交互已检查 原生重构和设备验收仍属于下一阶段')
cw=(W-2*M-62)/2;y=159
for p in DATA['release']:y=paragraph(p['title'],p['body'],M,y,cw,size=13)
x=M+cw+62;y=159
for n,item in enumerate(DATA['acceptance']):
    text(str(n+1).zfill(2),x,y,40,size=12,font='ARB',ink=WINE)
    y=text(item,x+43,y,cw-43,size=14,leading=23)+23

start('三套宣传调性的实际应用','宣传方向效果图','使用同一组产品能力 展示不同的表达重点 仅用于方向评审')
cw=(W-2*M-44)/3
for n,s in enumerate(DATA['schemes']):
    x=M+n*(cw+22)
    image(OUT/(s['id']+'-brand-direction.png'),x,159,cw,max_height=475)
    text(s['name'],x,656,cw,size=18,font='CNB')
    text(s['position'],x,695,cw,size=13,leading=21)
text('图片均为概念界面的宣传应用 不能直接作为正式 App 截图发布 选型后再完善渠道文案与素材',M,758,W-2*M,size=12,ink=SUB)

start('界面应该怎样影响宣传','传播与选型','先确定希望用户记住的价值 再确定官网 商店截图与社交内容的表达')
cw=(W-2*M-44)/3
for n,s in enumerate(DATA['schemes']):
    x=M+n*(cw+22)
    text(s['name'],x,161,cw,size=20,font='CNB')
    text(s['headline'],x,211,cw,size=27,font='CNB',ink=NAVY,leading=40)
    text(s['supporting'],x,310,cw,size=15,leading=25)
    text(s['marketing'],x,401,cw,size=14,leading=23)
rule(M,571,W-2*M)
text('我的初步建议',M,601,240,size=20,font='CNB')
text(DATA['conclusion'],M,646,W-2*M,size=16,leading=27)
text('明天评审先看三个问题  谁最需要这个 App  哪种操作愿意每天用  哪种画面能准确代表我们的承诺',M,755,W-2*M,size=12,ink=SUB)

start('交付范围与设计依据','交接说明','可复查的源稿 实现依据和素材来源')
cw=510;x2=650;y=159
y=paragraph('本次交付','三套独立方案，每套包含首页、战术白板和视频分析，共九张 2× PNG 效果图；三张独立总览；三张宣传方向应用；本 PDF；可交互原型；可编辑的设计内容、截图生成和 PDF 排版源稿。',M,y,cw,size=14)
y=paragraph('图像与功能说明','视频区域使用内置 ImageGen 生成的虚构成人练习静帧，没有使用真实用户或未成年人资料。原型中的播放与帧数变化仅用于评审控件；这不是实际视频、人体分析结果或原生性能证据。图标沿用已确认产品资产。',M,y,cw,size=14)
y=paragraph('当前代码依据','以下路径相对于 coach-insights 仓库。现有能力、状态与未验证项按实际文件阅读，设计建议不替代原验收记录。',M,y,cw,size=13)
for file in DATA['localEvidence']:y=text(file,M,y,cw,size=10.5,font='AR',leading=18)+4
y=159
y=paragraph('Apple 官方依据','侧栏折叠、检查器和笔输入可使用平台现有能力。这里列出的是可实施的技术方向，具体交互与系统版本表现仍要在本 App 中验证。',x2,y,W-M-x2,size=14)
for source in DATA['sources']:
    y=text(source['label'],x2,y,W-M-x2,size=13,font='ARB',leading=21)
    height=len(wrapped(source['url'],W-M-x2,10.5,'AR'))*17
    c.linkURL(source['url'],(x2,H-y-height,W-M,H-y),relative=0,thickness=0)
    y=text(source['url'],x2,y+4,W-M-x2,size=10.5,font='AR',ink=SUB,leading=17)+20
text('规范依据  公共品牌规范 1.1 与 2026-11-05 命名修订 1.2',x2,y+10,W-M-x2,size=12,ink=SUB)

finish();c.save()
reader=PdfReader(str(TARGET));assert len(reader.pages)==20,len(reader.pages)
extracted='\n'.join(p.extract_text() or '' for p in reader.pages)
for expected in ['棒球训练助手','原生资料库','专业工作室','轻松陪练','Apple Pencil','1.0.1']:
    assert expected in extracted,expected
(OUT/'qa/pdf-layout.json').write_text(json.dumps({'pages':checks,'pageCount':len(reader.pages),'passed':True},ensure_ascii=False,indent=2)+'\n')
(OUT/'manifest.json').write_text(json.dumps({'date':DATA['date'],'title':DATA['title'],'status':'design review only','files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.glob('*.png'))+[TARGET]},'source':'docs/design/ipad-first','screenCount':9,'pdfPages':20,'nativeImplementationChanged':False,'photo':'AI-generated adult demonstration still'},ensure_ascii=False,indent=2)+'\n')
print(TARGET)
