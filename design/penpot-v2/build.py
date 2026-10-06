#!/usr/bin/env python3
"""Fresh, editable AnkiMobile-parity design. No dependency on the earlier design.

Generate a neutral scene graph, SVG proofs and a responsive review prototype.
Penpot import uses native boards, text, geometry, components and token bindings.
All learning data is illustrative, never a user's collection.
"""
from pathlib import Path
import json, html, math

ROOT = Path(__file__).resolve().parent
LIGHT = dict(bg='#F6F7FA', surface='#FFFFFF', ink='#182337', muted='#637087', line='#E3E7EF', blue='#245BDB', tint='#EAF0FF', green='#19765C', greenSoft='#E8F5EF', orange='#9B5A16', orangeSoft='#FFF2DF', red='#B73D4A', redSoft='#FCECEF', violet='#7652B5', violetSoft='#F0EBFA', sidebar='#EFF2F8')
DARK = dict(bg='#111720', surface='#1B2431', ink='#EFF3FA', muted='#A7B3C6', line='#334053', blue='#91B2FF', tint='#283B60', green='#76CFAD', greenSoft='#223F38', orange='#EDC183', orangeSoft='#443728', red='#FFA5AF', redSoft='#482D37', violet='#C5AEF2', violetSoft='#392D51', sidebar='#161E2A')
SCREENS=[]
ICONS={
 'deck':'M4 7h16v13H4z M7 4h10 M8 11h8 M8 15h5',
 'search':'M16 16l5 5 M18 10a8 8 0 1 1-16 0a8 8 0 1 1 16 0',
 'stats':'M4 20V11h3v9 M10 20V4h3v16 M16 20V8h3v12',
 'settings':'M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M5 19l2-2 M17 7l2-2',
 'plus':'M12 4v16 M4 12h16', 'chevron':'M9 6l6 6-6 6', 'back':'M15 6l-6 6 6 6',
 'sync':'M20 7a9 9 0 0 0-15-2L2 8 M2 3v5h5 M4 17a9 9 0 0 0 15 2l3-3 M22 21v-5h-5',
 'check':'M5 12l4 4L20 5', 'more':'M4 12h1 M11 12h1 M18 12h1',
 'play':'M8 4l12 8-12 8z', 'pause':'M8 5v14 M16 5v14',
 'edit':'M4 17v4h4L20 9l-4-4z M13 8l4 4',
 'flag':'M5 22V3 M5 3h14l-3 5 3 5H5', 'star':'M12 2l3 7 7 1-5 5 1 7-6-4-6 4 1-7-5-5 7-1z',
 'clock':'M12 6v7l5 3 M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0',
 'cloud':'M6 18a5 5 0 0 1-1-10a7 7 0 0 1 13-1a5 5 0 0 1 1 11z',
 'download':'M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5',
 'upload':'M12 16V4 M7 9l5-5 5 5 M4 16v5h16v-5',
 'folder':'M3 6h7l2 3h9v11H3z', 'book':'M3 4h7l2 2 2-2h7v15h-7l-2 2-2-2H3z M12 6v15',
 'image':'M3 3h18v18H3z M3 16l6-6 5 5 3-3 4 4 M17 7h.1',
 'mic':'M9 3h6v11H9z M5 10v3a7 7 0 0 0 14 0v-3 M12 20v3',
 'undo':'M9 4L3 10l6 6 M3 10h11a7 7 0 0 1 7 7',
 'filter':'M3 4h18l-7 8v7l-4 2v-9z',
 'keyboard':'M2 5h20v14H2z M5 9h1 M9 9h1 M13 9h1 M17 9h1 M6 14h12',
 'pen':'M3 21l3-8L17 2l5 5L11 18z M6 13l5 5',
 'shield':'M12 2l9 4v7c0 5-9 9-9 9s-9-4-9-9V6z M8 12l3 3 5-6',
 'close':'M6 6l12 12 M18 6L6 18', 'tag':'M3 3h9l10 10-9 9L3 12z M8 8h.1',
 'user':'M16 7a4 4 0 1 1-8 0a4 4 0 1 1 8 0 M3 22v-3a9 9 0 0 1 18 0v3',
 'bell':'M5 17V9a7 7 0 0 1 14 0v8l2 2H3z M9 22h6',
 'split':'M3 3h18v18H3z M9 3v18', 'sun':'M12 7a5 5 0 1 0 0 10a5 5 0 1 0 0-10 M12 1v2 M12 21v2 M1 12h2 M21 12h2',
 'help':'M9 8a3 3 0 1 1 4 3v3 M12 18h.1 M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0',
}

class Canvas:
 def __init__(self,sid,title,w=390,h=844,page='01 iPhone',dark=False,section='deck',back=None):
  self.s={'id':sid,'title':title,'width':w,'height':h,'page':page,'dark':dark,'section':section,'nodes':[],'viewportHeight':h}; self.nodes=self.s['nodes']; self.c=DARK if dark else LIGHT; self.w=w;self.h=h;self.side=232 if w>=744 else 0;self.x=self.side+(32 if self.side else 20);self.cw=w-self.x-(32 if self.side else 20);self.y=142 if not self.side else 128
  self.rect(0,0,w,h,'bg',name='Canvas background')
  if self.side:self.sidebar(section)
  self.text(self.side+24,18,'9:41',13,bold=True,w=80)
  self.text(w-113,18,'Wi-Fi  •  100%',11,color='muted',w=100)
  if back:
   self.button(self.x,55,44,'','surface',icon='back',target=back); self.text(self.x+56,63,title,19 if len(title)>10 else 22,bold=True,w=self.cw-110)
  else:self.text(self.x,66,title,30,bold=True,w=self.cw-66)
  self.button(w-(76 if self.side else 64),56,44,'','surface',icon='plus' if section in ('deck','browse') else 'more',target='M09' if section in ('deck','browse') else 'M20')
  self.body_start=len(self.nodes)
 def color(self,c):return self.c.get(c,c)
 def rect(self,x,y,w,h,c='surface',r=0,name='Surface',stroke=None,kind='rect',target=None):
  n=dict(kind=kind,name=name,x=round(x,2),y=round(y,2),w=round(w,2),h=round(h,2),fill=self.color(c),token=c if c in self.c else None,r=r)
  if stroke:n['stroke']=self.color(stroke)
  if target:n['target']=target
  self.nodes.append(n);return n
 def text(self,x,y,t,size=15,color='ink',bold=False,w=None,align='left',name=None):
  lines=str(t).split('\n'); h=len(lines)*size*1.55+2
  n=dict(kind='text',name=name or str(t).replace('\n',' ')[:70],x=round(x,2),y=round(y,2),w=round(w if w is not None else max(30,len(str(t))*size*.9),2),h=round(h,2),text=str(t),size=size,weight=600 if bold else 400,fill=self.color(color),token=color if color in self.c else None,align=align)
  self.nodes.append(n);return n
 def icon(self,x,y,key,size=22,color='muted'):
  self.nodes.append(dict(kind='icon',name='Icon / '+key,x=x,y=y,w=size,h=size,path=ICONS.get(key,ICONS['more']),fill=self.color(color)))
 def line(self,x,y,w,color='line'):self.rect(x,y,w,1,color,name='Divider')
 def button(self,x,y,w,label,tone='blue',icon=None,target=None,h=48):
  w=max(44,w);h=max(44,h)
  n=self.rect(x,y,w,h,tone,14,name='Button / '+(label or icon or ''),target=target);n['component']='button';n['label']=label;n['icon']=icon;n['tone']=tone
  fg=('#142447' if self.s['dark'] else '#FFFFFF') if tone=='blue' else self.c['blue'] if tone=='tint' else self.c['ink']
  if icon:self.icon(x+(14 if label else (w-22)/2),y+(h-22)/2,icon,color=fg)
  if label:self.text(x+(42 if icon else 10),y+(h-24)/2,label,15,color=fg,bold=True,w=w-(54 if icon else 20),align='center' if not icon else 'left')
  return n
 def pill(self,x,y,label,tone='tint',w=None):
  w=w or (len(label)*12+22);self.rect(x,y,w,28,tone,8,name='Chip / '+label);self.text(x+9,y+4,label,12,color='blue' if tone=='tint' else 'muted',w=w-18);return w
 def card(self,x,y,w,h,title=None,sub=None):
  self.rect(x,y,w,h,'surface',18,stroke='line',name='Card / '+str(title or 'Content'))
  if title:self.text(x+20,y+17,title,16,bold=True,w=w-40)
  if sub:self.text(x+20,y+45,sub,12,color='muted',w=w-40)
 def row(self,x,y,w,label,value='',icon=None,target=None,tone=None,sub=None):
  h=68 if sub else 54
  self.rect(x,y,w,h,'surface',12,name='Row / '+label,target=target)
  if icon:self.icon(x+14,y+16,icon,21,color=tone or 'blue')
  tx=x+(48 if icon else 16); self.text(tx,y+13,label,14,color=tone or 'ink',w=w-(158 if value else 54))
  if sub:self.text(tx,y+38,sub,11,color='muted',w=w-65)
  if value in ('ON','OFF'):
   self.rect(x+w-63,y+15,43,25,'green' if value=='ON' else 'line',13,name='Switch / '+label)
   self.rect(x+w-(40 if value=='ON' else 61),y+17,21,21,'#FFFFFF',11,name='Switch thumb')
  elif value:self.text(x+w-152,y+16,value,12,color='muted',w=119,align='right')
  if target or value not in ('ON','OFF'):self.icon(x+w-28,y+17,'chevron',16)
  self.line(x+16,y+h-1,w-32);return y+h
 def section(self,y,title):self.text(self.x,y,title,12,color='muted',bold=True,w=self.cw);return y+30
 def rows(self,y,title,rows):
  y=self.section(y,title)
  for row in rows:y=self.row(self.x,y,self.cw,**row)
  return y+22
 def note(self,y,t,tone='tint',h=64):
  self.rect(self.x,y,self.cw,h,tone,14,name='Notice');self.text(self.x+14,y+12,t,12,color='blue' if tone=='tint' else 'muted',w=self.cw-28);return y+h+18
 def field(self,y,label,value,h=74):
  self.text(self.x,y,label,12,bold=True,color='muted',w=self.cw);y+=26
  self.rect(self.x,y,self.cw,h,'surface',12,stroke='line',name='Field / '+label);self.text(self.x+16,y+16,value,15,w=self.cw-32);return y+h+22
 def tabs(self):
  if self.side:return
  y=self.h-90;self.rect(0,y,self.w,90,'surface',name='Tab bar');self.line(0,y,self.w)
  for i,(key,label,target) in enumerate([('deck','デッキ','M01'),('browse','ブラウズ','M06'),('stats','統計','M14'),('settings','設定','M20')]):
   x=i*self.w/4;selected=self.s['section']==key;self.rect(x,y+3,self.w/4,61,'surface',name='Tab / '+label,target=target)
   if selected:self.rect(x+self.w/8-27,y+8,54,28,'tint',14)
   self.icon(x+self.w/8-10,y+11,'search' if key=='browse' else key,20,'blue' if selected else 'muted');self.text(x+2,y+42,label,10,'blue' if selected else 'muted',w=self.w/4-4,align='center')
  self.rect(self.w/2-55,self.h-13,110,4,'ink',2,name='Home indicator')
 def sidebar(self,active):
  self.rect(0,0,self.side,self.h,'sidebar',name='Sidebar / 232pt');self.text(24,54,'negoto',27,bold=True,w=175);self.text(24,96,'毎日の記憶を、少しずつ。',11,color='muted',w=184)
  for i,(key,title,target,ic) in enumerate([('deck','デッキ','I01','deck'),('browse','ブラウズ','I04','search'),('stats','統計','I05','stats'),('settings','設定','I09','settings')]):
   yy=156+i*56;self.rect(14,yy,204,46,'tint' if key==active else 'sidebar',12,name='Sidebar / '+title,target=target);self.icon(30,yy+12,ic,21,'blue' if key==active else 'muted');self.text(65,yy+11,title,15,color='blue' if key==active else 'ink',bold=key==active,w=140)
  self.text(24,412,'マイデッキ',11,bold=True,color='muted',w=170)
  for i,t in enumerate(['英語・毎日のことば','日本史','からだのしくみ']):self.row(12,444+i*49,208,t,icon='folder',target='I02')
  self.button(16,self.h-144,200,'AnkiWebと同期','surface',icon='sync',target='M24')
  self.icon(24,self.h-67,'user',24);self.text(60,self.h-72,'個人プロフィール',13,bold=True,w=157);self.text(60,self.h-48,'最終同期  9:38',11,color='muted',w=157)
 def finish(self,tab=True):
  # Keep every designed state above the persistent tab bar. This adjusts the
  # initial drawing's vertical rhythm; native resize rules are in import.js.
  if tab and not self.side and self.nodes[self.body_start:]:
   bottom=max(n['y']+n['h'] for n in self.nodes[self.body_start:])
   limit=self.h-104
   if bottom>limit:
    scale=(limit-self.y)/(bottom-self.y)
    self.s['verticalRhythmScale']=round(scale,4)
    for n in self.nodes[self.body_start:]:
     n['y']=round(self.y+(n['y']-self.y)*scale,2)
     if n['kind']=='rect':n['h']=round(max(44 if n.get('target') and n['h']>=44 else 1,n['h']*scale),2)
  self.s['hasTabBar']=tab and not self.side
  if tab:self.tabs()
  SCREENS.append(self.s);return self.s

def bar_chart(c,x,y,w,h,values=None,labels=('月','火','水','木','金','土','日'),stack=True):
 vals=values or [72,94,65,120,87,103,84]; mx=max(vals)*1.12;left=28;bottom=y+h-25
 for frac in [0,.5,1]:
  yy=bottom-(h-42)*frac;c.line(x+left,yy,w-left);c.text(x,yy-7,str(round(mx*frac)),9,color='muted',w=24)
 step=(w-left)/len(vals);bw=min(30,step*.55)
 for i,v in enumerate(vals):
  hh=(h-42)*v/mx;xx=x+left+step*i+(step-bw)/2
  c.rect(xx,bottom-hh,bw,hh,'blue',4,name='Chart / review count '+str(v))
  if stack:c.rect(xx,bottom-hh,bw,hh*.25,'green',4,name='Chart / learning share')
  if i<len(labels):c.text(xx-10,bottom+8,labels[i],10,color='muted',w=bw+20,align='center')

def heatmap(c,x,y,w,cols=15,rows=4):
 gap=4;sz=min(16,(w-(cols-1)*gap)/cols)
 for col in range(cols):
  for row in range(rows):
   tone=['line','tint','blue','greenSoft','green'][(col*7+row*3)%5]
   c.rect(x+col*(sz+gap),y+row*(sz+gap),sz,sz,tone,3,name='Calendar / sample day')

def metrics(c,x,y,w,items):
 gap=10;cw=(w-gap*(len(items)-1))/len(items)
 for i,(num,label,col) in enumerate(items):
  xx=x+i*(cw+gap);c.card(xx,y,cw,90);c.text(xx+14,y+12,num,23 if cw<120 and len(num)>4 else 28,color=col,bold=True,w=cw-28);c.text(xx+14,y+57,label,11,color='muted',w=cw-28)

def decks(c):
 x,y,w=c.x,c.y,c.cw
 c.text(x,y-16,'10月6日 火曜日  ·  おかえりなさい',12,color='muted',w=w)
 split=c.w>=1024;heroW= w*.61 if split else w
 c.rect(x,y+21,heroW,196,'blue',22,name='Today / Study invitation')
 fg='#142447' if c.s['dark'] else '#FFFFFF'
 c.text(x+22,y+42,'今日の学習',14,color=fg,w=heroW-44);c.text(x+22,y+74,'84',52,color=fg,bold=True,w=130);c.text(x+133,y+107,'枚の復習',15,color=fg,w=150)
 c.text(x+22,y+139,'新規 20   /   学習中 8   /   約12分',12,color=fg,w=heroW-44)
 c.button(x+22,y+163,heroW-44,'学習をはじめる','surface',icon='play',target='I03' if c.side else 'M03',h=40)
 if split:
  xx=x+heroW+20;ww=w-heroW-20;c.card(xx,y+21,ww,196,'続けた日々','今週は5日、学習しました');heatmap(c,xx+20,y+99,ww-40,cols=10,rows=3);c.text(xx+20,y+168,'14日連続  ·  合計 1,248回答',11,color='muted',w=ww-40)
 yy=y+239;c.text(x,yy,'マイデッキ',18,bold=True,w=180);c.text(x+w-94,yy+4,'すべて表示',12,color='blue',w=94,align='right');yy+=39
 for i,(name,sub,new,due,tone) in enumerate([('英語・毎日のことば','3つのサブデッキ',12,48,'blue'),('日本史','古代から近現代まで',5,24,'violet'),('からだのしくみ','画像とことばで学ぶ',3,12,'green')]):
  c.card(x,yy,w,81);c.rect(x+15,yy+17,44,44,tone,13);c.icon(x+26,yy+28,'book',22,'#FFFFFF');c.text(x+73,yy+14,'英語・毎日の…' if w<320 and i==0 else name,15,bold=True,w=w-171);c.text(x+73,yy+43,sub,11,color='muted',w=w-160);c.text(x+w-87,yy+13,str(due),23,color='green',bold=True,w=57,align='right');c.text(x+w-105,yy+47,f'新規 {new}',11,color='blue',w=75,align='right');c.rect(x,yy,w,81,'#FFFFFF',18,name='Open deck',target='I02' if c.side else 'M02')['opacity']=0;yy+=94
 c.button(x,yy+2,w,'デッキの作成・読み込み','surface',icon='plus',target='M27',h=44)

def deck_detail(c):
 x,y,w=c.x,c.y,c.cw;c.pill(x,y,'英語 / Vocabulary');c.text(x,y+54,'毎日のことば',30,bold=True,w=w);c.text(x,y+103,'一つひとつのことばを、使える記憶に。',13,color='muted',w=w)
 metrics(c,x,y+146,w,[('48','復習','green'),('8','学習中','orange'),('12','新規','blue')]);c.button(x,y+262,w,'68枚を学習する','blue',icon='play',target='I03' if c.side else 'M03')
 yy=y+334
 for label,ic,target,val in [('カードを見る','search','I04' if c.side else 'M06','1,248枚'),('デッキの統計','stats','I05' if c.side else 'M14',''),('学習オプション','settings','M30','FSRS'),('カスタム学習','filter','M33',''),('デッキの管理','folder','M43','')]:yy=c.row(x,yy,w,label,val,ic,target)

def review(c,answer=False,typed=False,scratch=False):
 x,y,w=c.x,c.y,c.cw
 c.text(x,y-20,'英語・毎日のことば',13,color='muted',w=w-140);c.text(x+w-125,y-20,'12 新規   8 学習   48 復習',9,color='muted',w=125,align='right')
 c.rect(x,y+15,w,4,'line',2);c.rect(x,y+15,w*.38,4,'blue',2)
 cardW=min(640,w);xx=x+(w-cardW)/2;yy=y+45;hh=398 if c.h>=750 else 210
 if scratch:cardW=min(530,w*.58);xx=x
 c.card(xx,yy,cardW,hh);c.pill(xx+22,yy+22,'EN → JP');c.icon(xx+cardW-48,yy+26,'flag',20,'orange');c.text(xx+24,yy+113,'serendipity',36,bold=True,w=cardW-48,align='center');c.text(xx+24,yy+172,'/ˌser.ənˈdɪp.ə.ti/',14,color='muted',w=cardW-48,align='center')
 c.button(xx+cardW/2-70,yy+214,140,'音声を再生','tint',icon='play',target='M39',h=44)
 if answer:
  c.line(xx+24,yy+280,cardW-48);c.text(xx+24,yy+300,'思いがけない幸運',23,bold=True,w=cardW-48,align='center');c.text(xx+24,yy+345,'A beautiful discovery by chance.',12,color='muted',w=cardW-48,align='center')
 elif typed:
  c.rect(xx+24,yy+286,cardW-48,54,'bg',12,stroke='blue',name='Type answer');c.text(xx+40,yy+300,'答えを入力…',15,color='muted',w=cardW-80)
 else:c.text(xx+24,yy+318,'思い出してから、答えを確認',13,color='muted',w=cardW-48,align='center')
 if scratch:
  sx=xx+cardW+20;sw=w-cardW-20;c.card(sx,yy,sw,hh,'手書きメモ','Apple Pencil  ·  このカードだけ');c.text(sx+34,yy+140,'幸',92,color='blue',w=sw-68,align='center');c.button(sx+16,yy+hh-65,sw-32,'取り消す・消去','tint',icon='undo',target='M38')
 by=c.h-134 if c.h>=750 else c.h-96
 if answer:
  gap=8;bw=(w-3*gap)/4
  for i,(label,time,tone) in enumerate([('もう一度','1分','redSoft'),('難しい','6分','orangeSoft'),('普通','1日','greenSoft'),('簡単','4日','tint')]):
   bx=x+i*(bw+gap);c.rect(bx,by,bw,65,tone,13,name='Answer / '+label,target='M05');c.text(bx+3,by+8,time,12,color='muted',w=bw-6,align='center');c.text(bx+3,by+32,label,13,bold=True,w=bw-6,align='center')
 else:c.button(x,by,w,'答えを見る','blue',target='I03A' if c.side else 'M04',h=56)
 for i,(lab,ic,target) in enumerate([('元に戻す','undo','M03'),('編集','edit','M10'),('ツール','settings','M37')]):
  bx=x+i*w/3;c.icon(bx+w/6-35,c.h-49,ic,18);c.text(bx+w/6-8,c.h-50,lab,11,color='muted',w=75);c.rect(bx,c.h-59,w/3,44,'#FFFFFF',name='Action / '+lab,target=target)['opacity']=0

def browse(c,select=False):
 x,y,w=c.x,c.y,c.cw; wide=c.w>=1024; lw=350 if wide else w
 c.rect(x,y,lw,48,'surface',13,stroke='line');c.icon(x+14,y+13,'search',20);c.text(x+44,y+13,'deck:英語 is:due',14,w=lw-96);c.rect(x,y,lw,48,'#FFFFFF',name='Open search',target='M07')['opacity']=0
 c.button(x+lw-45,y+2,42,'','surface',icon='filter',target='M07',h=44)
 c.pill(x,y+61,'復習待ち 48');c.pill(x+117,y+61,'タグ',w=66);c.text(x+lw-86,y+67,'選択' if not select else '選択解除',12,color='blue',w=86,align='right');c.rect(x+lw-98,y+55,98,44,'#FFFFFF',name='Select cards',target='M08')['opacity']=0
 c.text(x,y+111,'表面 / 裏面',11,color='muted',w=lw-140);c.text(x+lw-132,y+111,'期限順  ↓',11,color='muted',w=132,align='right')
 items=[('serendipity','思いがけない幸運','今日'),('resilience','立ち直る力','今日'),('ephemeral','つかの間の','今日'),('curiosity','好奇心','今日'),('tranquil','穏やかな','今日'),('perspective','ものの見方','明日')]
 for i,(a,b,due) in enumerate(items):
  yy=y+142+i*77;c.rect(x,yy,lw,72,'tint' if i==0 or select and i<3 else 'surface',12,name='Card row / '+a,target='M10');tx=x+16
  if select:c.rect(tx,yy+24,22,22,'blue' if i<3 else 'surface',6,stroke='line');tx+=34
  c.text(tx,yy+10,a,16,bold=True,w=lw-115);c.text(tx,yy+39,b,12,color='muted',w=lw-115);c.text(x+lw-63,yy+26,due,11,color='green',w=50,align='right')
 if select:c.button(x,c.h-155,lw,'3枚を操作する','blue',target='M08A')
 if wide:
  dx=x+lw+24;dw=w-lw-24;c.card(dx,y,dw,555,'カードのプレビュー','基本（表裏）  ·  英語・毎日のことば');c.text(dx+22,y+132,'serendipity',32,bold=True,w=dw-44,align='center');c.text(dx+22,y+200,'思いがけない幸運',21,w=dw-44,align='center');c.line(dx+24,y+290,dw-48);c.text(dx+24,y+316,'次回の復習     今日\n間隔                 12日\n安定性              14.2日\nタグ                 vocabulary, unit-04',14,color='muted',w=dw-48);c.button(dx+20,y+482,dw-40,'ノートを編集','blue',icon='edit',target='I06')

def editor(c,cloze=False):
 x,y,w=c.x,c.y,c.cw; full=w;c.cw=min(w,550) if w>=790 else (w-24)*.55 if c.w>=1024 else w;ew=c.cw
 c.pill(x,y,'穴埋め' if cloze else '基本（表裏）',w=120);c.pill(x+130,y,'英語  ▾',w=ew-130)
 yy=c.field(y+52,'テキスト' if cloze else '表面','The {{c1::mitochondrion}}\nis the powerhouse of the cell.' if cloze else 'serendipity',h=112 if cloze else 88)
 yy=c.field(yy,'補足' if cloze else '裏面','思いがけない幸運\nA beautiful discovery by chance.',h=112)
 c.rect(x,yy,ew,48,'surface',12,stroke='line');c.text(x+14,yy+10,'B   I   U   色   x₂   √   [ … ]   </>',16,w=ew-28);yy+=64
 for i,(label,ic,target) in enumerate([('メディア','image','M39'),('プレビュー','play','M04'),('テンプレート','edit','M12')]):c.button(x+i*ew/3,yy,ew/3-5,label,'tint',icon=None,target=target,h=44)
 yy=c.field(yy+66,'タグ','vocabulary   unit-04',h=48);c.text(x,yy,'重複なし  ·  ノートから1枚のカードを作成',11,color='green',w=ew);c.button(x,c.h-149,ew,'ノートを保存','blue',target='M06')
 if c.w>=1024:
  dx=x+ew+24;dw=full-ew-24;c.card(dx,y,dw,455,'プレビュー','保存前に表面と裏面を確認');c.text(dx+20,y+150,'serendipity',30,bold=True,w=dw-40,align='center');c.text(dx+20,y+219,'思いがけない幸運',19,w=dw-40,align='center');c.button(dx+18,y+375,dw-36,'表面 / 裏面を切り替え','tint',target='M04')
 c.cw=full

def stats(c,kind='overview'):
 x,y,w=c.x,c.y,c.cw;wide=c.w>=1024
 c.pill(x,y,'すべてのデッキ  ▾',w=174);c.pill(x+184,y,'30日  ▾',w=94);c.text(x,y+47,'9月7日 – 10月6日  ·  サンプルデータ',11,color='muted',w=w)
 if kind=='overview':
  metrics(c,x,y+80,w,[('1,248','回答回数','ink'),('92.4%','正答率','green'),('14日','連続学習','blue')])
  cw=(w-20)/2 if wide else w;c.card(x,y+192,cw,257,'学習の記録','回答回数 / 日');bar_chart(c,x+18,y+257,cw-36,163)
  xx=x+cw+20 if wide else x;yy=y+192 if wide else y+468;c.card(xx,yy,cw,145,'続けた日々');heatmap(c,xx+20,yy+58,cw-40,cols=18 if wide else 15,rows=3)
  if wide:
   c.card(xx,yy+164,cw,244,'回答の内訳','回答回数。ユニークなカード数ではありません。');answer_bars(c,xx+20,yy+233,cw-40)
   c.button(x,y+472,cw,'詳細な統計を見る','tint',target='I07')
  else:c.button(x,y+627,w,'復習予定・定着率・分布を見る','tint',target='M15',h=44)
 elif kind=='forecast':
  metrics(c,x,y+80,w,[('68','今日の予定','green'),('43','1日の負荷','blue')]);c.card(x,y+192,w,273,'これからの復習','予定枚数 / 日  ·  新規学習を増やさない場合');bar_chart(c,x+18,y+269,w-36,170,[68,52,41,57,39,47,44],['今日','7','8','9','10','11','12'],False);c.note(y+483,'期限超過 16枚は別集計。\n将来の予定は学習結果によって変わります。');c.button(x,y+566,w,'定着率を見る','tint',target='M16');c.button(x,y+625,w,'カードの分布を見る','surface',target='M17',h=44)
 elif kind=='retention':
  metrics(c,x,y+80,w,[('91.8%','実測の定着率','green'),('90%','FSRSの目標','blue')]);c.card(x,y+191,w,236,'実測の定着率','同じカードの、その日最初の復習で集計')
  for i,(lab,young,mature) in enumerate([('期間','未成熟','成熟'),('今日','89.1%','93.2%'),('7日間','90.5%','94.0%'),('30日間','90.2%','93.8%')]):
   yy=y+259+i*37;c.text(x+18,yy,lab,12,color='muted' if i==0 else 'ink',w=w*.34);c.text(x+w*.43,yy,young,12,w=w*.23);c.text(x+w*.72,yy,mature,12,w=w*.23)
  c.card(x,y+445,w,196,'回答ボタンの使用');answer_bars(c,x+20,y+499,w-40);c.button(x,y+653,w,'時間帯と所要時間を見る','tint',target='M18',h=44)
 elif kind=='distribution':
  c.card(x,y+80,w,180,'カードの構成','合計 2,480枚');vals=[('成熟',1240,'green'),('未成熟・学習',684,'blue'),('新規',420,'violet'),('停止中',136,'muted')];pos=x+20
  for label,v,col in vals:ww=(w-40)*v/2480;c.rect(pos,y+149,ww,20,col,3);pos+=ww
  for i,(label,v,col) in enumerate(vals):xx=x+20+(i%2)*(w-40)/2;yy=y+185+(i//2)*28;c.rect(xx,yy+5,7,7,col,2);c.text(xx+14,yy,f'{label}  {v:,}',11,w=(w-40)/2-18)
  c.card(x,y+282,w,230,'FSRS：記憶の安定性','カード数 / 次回の定着までの日数');bar_chart(c,x+18,y+348,w-36,145,[25,68,92,74,36,20],['1日','7日','14日','30日','90日','1年'],False)
  c.button(x,y+533,w,'難易度・想起確率・復習間隔','tint',target='M19');c.note(y+599,'FSRSが無効の場合は「易しさ」を表示。\n各グラフから対象カードを検索できます。',h=68)
 elif kind=='time':
  metrics(c,x,y+80,w,[('3.8時間','30日間の学習時間','ink'),('11秒','1回答の平均時間','blue')]);c.card(x,y+193,w,273,'時間帯別の学習','回答数 / 時間帯');bar_chart(c,x+18,y+266,w-36,168,[5,13,74,22,17,39,96],['0時','4','8','12','16','20','23'],False);c.note(y+483,'棒を選択すると、回答数と正答率を表示。\n学習時間は日・週・月で集計できます。');c.button(x,y+569,w,'統計の概要に戻る','tint',target='M14')
 else:
  cw=(w-20)/2 if wide else w
  for i,(title,sub) in enumerate([('難易度','カード数 / 0–100%'),('想起確率','カード数 / 0–100%'),('復習間隔','カード数 / 日'),('易しさ（FSRS無効時）','カード数 / 係数')]):
   xx=x+(i%2)*(cw+20) if wide else x;yy=y+80+(i//2)*275 if wide else y+80+i*148;hh=250 if wide else 137;c.card(xx,yy,cw,hh,title,sub);bar_chart(c,xx+18,yy+61,cw-36,hh-67,[15,35,77,92,62,27],['0','20','40','60','80','100'],False)

def answer_bars(c,x,y,w):
 for i,(lab,n,col) in enumerate([('もう一度',95,'red'),('難しい',173,'orange'),('普通',815,'green'),('簡単',165,'blue')]):
  yy=y+i*27;c.text(x,yy,lab,11,color='muted',w=65);c.rect(x+74,yy+3,(w-123)*n/815,13,col,4);c.text(x+w-42,yy,str(n),11,w=42,align='right')

def standard(sid,title,groups,notice=None,back='M20',section='settings',w=390,h=844,page='01 iPhone'):
 c=Canvas(sid,title,w,h,page,section=section,back=back);y=c.y
 if notice:y=c.note(y,notice)
 for title,rows in groups:y=c.rows(y,title,rows)
 c.finish();return c

def rows(*specs):
 return [dict(label=s if isinstance(s,str) else s[0],value=s[1] if not isinstance(s,str) and len(s)>1 else '',target=s[2] if not isinstance(s,str) and len(s)>2 else None,icon=s[3] if not isinstance(s,str) and len(s)>3 else None) for s in specs]

def make_screens():
 c=Canvas('M01','デッキ');decks(c);c.finish()
 c=Canvas('M02','デッキの詳細',back='M01');deck_detail(c);c.finish()
 for sid,ans,typed,title in [('M03',False,False,'学習'),('M04',True,False,'学習'),('M03T',False,True,'入力して答える')]:c=Canvas(sid,title,back='M02');review(c,ans,typed);c.finish(False)
 c=Canvas('M05','今日の学習',back='M01');x,y,w=c.x,c.y,c.cw;c.rect(x+w/2-40,y+39,80,80,'greenSoft',40);c.icon(x+w/2-21,y+59,'check',42,'green');c.text(x,y+155,'今日も、おつかれさま。',25,bold=True,w=w,align='center');c.text(x,y+204,'学んだことが、また一つ記憶に。',13,color='muted',w=w,align='center');metrics(c,x,y+262,w,[('68','回答','blue'),('12分','学習時間','ink'),('94%','正答率','green')]);c.button(x,y+393,w,'デッキに戻る','blue',target='M01');c.button(x,y+458,w,'もう少し学習する','tint',target='M33');c.text(x,y+532,'次の学習カードは10分後です。',12,color='muted',w=w,align='center');c.finish()
 for sid,sel in [('M06',False),('M08',True)]:c=Canvas(sid,'ブラウズ',section='browse');browse(c,sel);c.finish()
 standard('M07','検索と絞り込み',[('検索条件',rows(('デッキ','英語'),('状態','復習待ち'),('タグ','vocabulary'),('フラグ','すべて'),('ノートタイプ','すべて'))),('検索と表示',rows(('保存済み検索','4件'),('並び順・表示列','期限 / 表面')))],notice='deck:英語 is:due\nAND / OR / 正規表現を使った検索に対応。',back='M06',section='browse')
 standard('M08A','3枚のカードを操作',[('カードへの操作',rows(('デッキを変更','','M43'),('期限を設定・新規に戻す','','M41'),('停止・停止解除'),('埋める・埋め戻す'),('フラグを設定'))),('ノートへの操作',rows(('タグを追加・削除'),('ノートタイプを変更','','M13'),('ノートを削除','','M44')))],back='M08',section='browse')
 for sid,title,cloze in [('M09','ノートを追加',False),('M10','ノートを編集',False),('M11','穴埋めノート',True)]:c=Canvas(sid,title,section='browse',back='M06');editor(c,cloze);c.finish()
 c=Canvas('M12','カードテンプレート',section='browse',back='M10');x,y,w=c.x,c.y,c.cw;c.pill(x,y,'表面',w=100);c.pill(x+111,y,'裏面',tone='surface',w=100);c.pill(x+222,y,'CSS',tone='surface',w=w-222);c.card(x,y+50,w,220);c.text(x+16,y+70,'1   <div class="word">\n2     {{Front}}\n3   </div>\n4   {{tts en_US:Front}}\n5   <hr id="answer">\n6   {{Back}}',13,color='blue',w=w-32);c.card(x,y+293,w,175,'プレビュー');c.text(x+20,y+361,'serendipity',28,bold=True,w=w-40,align='center');c.button(x,y+490,w,'カードの種類・フィールド','tint',target='M13');c.note(y+560,'HTML / CSS / JavaScript / MathJaxに対応。\n表裏の追加、並べ替え、条件付き表示を設定。');c.finish()
 standard('M13','ノートタイプ',[('タイプの管理',rows(('基本（表裏）','2フィールド'),('基本（逆方向も）','2カード'),('穴埋め','Cloze','M11'),('画像穴埋め','Image Occlusion','M40'))),('フィールドとカード',rows(('フィールドの追加・並べ替え','','M13F'),('タイプの複製・名前の変更'),('カード生成とテンプレート','','M12')))],back='M10',section='browse')
 standard('M13F','フィールドの設定',[('基本（表裏）',rows(('表面','1'),('裏面','2'),('フィールドを追加'))),('選択中：表面',rows(('検索・並び替えに使用','ON'),('前の入力を保持','OFF'),('入力方向','左から右'),('編集フォント','システム'),('HTMLで編集','OFF')))],back='M13',section='browse')
 for sid,title,kind in [('M14','統計','overview'),('M15','復習の予定','forecast'),('M16','定着率と回答','retention'),('M17','カードの分布','distribution'),('M18','学習時間','time'),('M19','記憶の分布','advanced')]:c=Canvas(sid,title,section='stats',back=None if sid=='M14' else 'M14');stats(c,kind);c.finish()
 standard('M20','設定',[('学習',rows(('学習画面と音声','','M21','play'),('タップ・スワイプ','','M22','edit'),('キーボード・ゲームパッド','','M23','keyboard'),('表示・通知・一般','','M21G','sun'))),('データ',rows(('AnkiWebと同期','同期済み','M24','sync'),('プロフィール','個人','M35','user'),('バックアップとメンテナンス','','M36','shield'))),('サポート',rows(('ヘルプ・外部連携','','M42','help')))],back=None)
 standard('M21','学習画面と音声',[('表示',rows(('回答時のフィードバック','ON'),('上部・下部バー','表示','M21B'),('ズームを回答後も維持','OFF'),('回答入力を無効にする','OFF'))),('音声と操作',rows(('音声の自動再生','ON'),('消音モードでも再生','OFF'),('ダブルタップ防止','300ms'),('シェイク時の動作','元に戻す')))],back='M20')
 standard('M21B','バーと学習ツール',[('上部バー',rows(('上部バーを表示','ON'),('ボタンと並び順','編集・戻す'),('ツールボタンの位置','右'))),('下部バー',rows(('下部バーを表示','ON'),('残り枚数','ON'),('回答ボタン','ON'),('次回までの時間','ON'),('回答ボタンのサイズ','標準')))],back='M21')
 standard('M21G','表示・通知・一般',[('外観と通知',rows(('テーマ','システム','M45'),('文字の大きさ','標準','R06'),('リマインダー','毎日 20:00'),('インターフェースの言語','日本語'))),('スケジュールとメディア',rows(('1日の開始','04:00'),('先取り学習','20分'),('画像の最大辺','1,024px'),('貼り付け画像も縮小','ON')))],back='M20')
 c=Canvas('M22','タップとスワイプ',section='settings',back='M20');x,y,w=c.x,c.y,c.cw;c.pill(x,y,'問題の表示中',w=w/2-5);c.pill(x+w/2+5,y,'解答の表示中','surface',w=w/2-5);c.text(x,y+54,'領域ごとに動作を割り当て',13,color='muted',w=w)
 for i in range(9):xx=x+(i%3)*(w+8)/3;yy=y+88+(i//3)*70;c.rect(xx,yy,(w-16)/3,62,'tint',12);c.text(xx+4,yy+21,'答えを表示',11,color='blue',w=(w-16)/3-8,align='center')
 yy=y+330
 for lab,val in [('左へスワイプ','ツール'),('右へスワイプ','デッキに戻る'),('上へスワイプ','音声を再生'),('下へスワイプ','無効')]:yy=c.row(x,yy,w,lab,val)
 c.note(yy+16,'縦スワイプは画面の端から開始。\nカード本文のスクロールと区別します。');c.finish()
 standard('M23','外部入力',[('キーボード',rows(('答えを表示','Space'),('回答を選ぶ','1 / 2 / 3 / 4'),('元に戻す','⌘ Z'),('検索・追加','⌘ F / ⌘ N'))),('ゲームパッド',rows(('接続中','8BitDo'),('A / B / X / Y','回答を割当'),('十字キー・肩ボタン','ツールを割当'),('ユーザーアクション','1–8')))],back='M20')
 standard('M24','AnkiWebと同期',[('アカウント',rows(('ログイン中','user@example.com','M25'),('今すぐ同期','9:38に完了','M24P','sync'))),('同期の設定',rows(('音声と画像も同期','ON'),('一方向の同期','','M26'),('オフラインの変更','16件保留')))],notice='すべてのデバイスで同じ記憶を。\nカード・学習履歴・メディアを同期します。',back='M20')
 c=Canvas('M25','AnkiWebにログイン',section='settings',back='M24');y=c.note(c.y,'AnkiWebアカウントを使って\niPhone・iPad・パソコンをつなぎます。');y=c.field(y,'メールアドレス','user@example.com',54);y=c.field(y,'パスワード','••••••••••••',54);c.button(c.x,y,c.cw,'ログイン','blue',target='M24');c.button(c.x,y+64,c.cw,'アカウント作成・パスワードの再設定','tint',target='M42');c.finish()
 c=Canvas('M24P','同期しています',section='settings',back='M24');x,y,w=c.x,c.y,c.cw;c.icon(x+w/2-36,y+65,'sync',72,'blue');c.text(x,y+177,'カードの同期が完了',22,bold=True,w=w,align='center');c.text(x,y+226,'メディア 128 / 184ファイル',13,color='muted',w=w,align='center');c.rect(x,y+280,w,8,'line',4);c.rect(x,y+280,w*.69,8,'blue',4);c.note(y+321,'同期中でも学習を続けられます。\n接続が切れた場合は、ここから再開します。');c.button(x,y+418,w,'学習に戻る','blue',target='M01');c.finish()
 c=Canvas('M26','同期するデータを選択',section='settings',back='M24');x,y,w=c.x,c.y,c.cw;c.note(y,'コレクション全体を置き換える同期です。\n残したいデータがある方を選んでください。','orangeSoft',76)
 for i,(title,sub) in enumerate([('このiPhoneを残す','2,480枚  ·  最終更新 今日 9:41\nAnkiWebのカードと履歴を置き換え'),('AnkiWebを残す','2,492枚  ·  最終更新 今日 9:30\nこの端末のカードと履歴を置き換え')]):c.card(x,y+105+i*158,w,138,title);c.text(x+20,y+152+i*158,sub,12,color='muted',w=w-40);c.rect(x,y+105+i*158,w,138,'#FFFFFF',name='Choose sync source',target='M26C')['opacity']=0
 c.button(x,y+452,w,'キャンセル','surface',target='M24');c.text(x,y+530,'音声と画像は通常のメディア同期が続きます。',11,color='muted',w=w);c.finish()
 standard('M26C','置き換えの確認',[('今回の操作',rows(('残すデータ','このiPhone'),('置き換える場所','AnkiWeb'),('カードと学習履歴','2,480枚'))),('続行',rows(('バックアップを作成して実行','','M24P','shield'),('キャンセル','','M24')))],notice='AnkiWeb側の変更は上書きされます。\n実行前のデータをバックアップに保存します。',back='M26')
 standard('M27','追加と読み込み',[('新しく作る',rows(('デッキを作成','','M43','folder'),('ノートを追加','','M09','plus'),('共有デッキを探す','','M29','search'))),('読み込む',rows(('ファイルから','APKG / COLPKG','M28','download'),('テキストから','CSV / TSV','M28T'),('AirDrop・ファイル共有','','M28'))),('書き出す',rows(('デッキ・コレクションを書き出す','','M28E','upload')))],back='M01',section='deck')
 standard('M28','読み込みの確認',[('英語基礎.apkg',rows(('追加するノート','240件'),('更新するノート','12件'),('重複の処理','既存を更新'),('学習履歴を読み込む','ON'),('読み込み先','英語'))),('実行',rows(('252件を読み込む','','M01','download')))],notice='デッキの追加・更新です。\nCOLPKGの場合は全体の置き換えを確認します。',back='M27',section='deck')
 standard('M28T','テキストの読み込み',[('形式',rows(('区切り文字','カンマ'),('文字コード','UTF-8'),('1行目は見出し','ON'),('HTMLを許可','OFF'))),('列の対応',rows(('1列目：word','表面'),('2列目：meaning','裏面'),('3列目：tags','タグ'))),('プレビュー',rows(('240件を読み込む','','M01','download')))],back='M27',section='deck')
 standard('M28E','書き出す',[('対象と形式',rows(('対象','すべてのデッキ'),('形式','COLPKG'),('学習スケジュールを含める','ON'),('音声・画像を含める','ON'))),('保存先',rows(('ファイルに保存','','M01','folder'),('共有・AirDrop','','M01','upload')))],notice='デッキ単位はAPKG、全体はCOLPKG。\n共有前に対象と含めるデータを確認。',back='M27',section='deck')
 c=Canvas('M29','共有デッキ',section='deck',back='M27');x,y,w=c.x,c.y,c.cw;c.rect(x,y,w,48,'surface',12,stroke='line');c.icon(x+13,y+13,'search',20);c.text(x+45,y+12,'学びたいテーマを検索',14,color='muted',w=w-60);c.note(y+67,'AnkiWebの共有デッキを開きます。\n公開者の説明と内容を確認して読み込み。')
 for i,(title,sub) in enumerate([('英語','語彙・発音・フレーズ'),('医学・生物','解剖・生理・画像'),('言語を探す','日本語・中国語・フランス語')]):c.card(x,y+158+i*119,w,104,title,sub);c.text(x+20,y+227+i*119,'AnkiWebで見る  ↗',12,color='blue',w=w-40)
 c.finish()
 standard('M30','学習オプション',[('プリセット：毎日の学習',rows(('プリセットの管理','3デッキで使用'),('新規 / 日','20'),('復習の上限 / 日','200'),('適用範囲','プリセット'))),('スケジュール',rows(('FSRS','有効','M31'),('学習・再学習ステップ','','M32'),('表示順と兄弟カード','','M32O'),('自動送り・タイマー','','M32A')))],back='M02')
 standard('M31','FSRS',[('記憶のモデル',rows(('FSRSを使用','ON'),('目標の保持率','90%'),('パラメータの最適化','','M31P'),('パラメータを評価','','M31P'),('変更時に再スケジュール','OFF'))),('詳細',rows(('最大間隔','36,500日'),('過去の復習を除外','なし'),('簡単な日・負荷調整','','M31P')))],notice='保持率を高くすると復習量が増えます。\n最適化はこれまでの学習履歴を使います。',back='M30')
 standard('M31P','FSRSの詳細',[('最適化のプレビュー',rows(('対象の復習','8,420件'),('モデルの評価','実行'),('最適化した値を適用'),('負荷のシミュレーション'))),('学習量の調整',rows(('月–金','通常'),('土・日','少なめ'),('再スケジュールを確認'),('パラメータを初期化')))],back='M31')
 standard('M32','学習と忘却',[('学習ステップ',rows(('新規カード','1分 10分'),('再学習','10分'),('先取り','20分'))),('苦手なカード',rows(('Leechのしきい値','8回'),('Leechへの動作','停止してタグ付け'))),('FSRS無効時の設定',rows(('卒業間隔 / 簡単の間隔','1日 / 4日'),('初期の易しさ / 間隔補正','250% / 100%'),('忘却後の最小間隔','1日')))],back='M30')
 standard('M32O','順序と兄弟カード',[('カードの表示順',rows(('新規の取得順','デッキ順'),('新規の並び順','取得順'),('新規と復習','復習の後'),('翌日以降の学習','復習と混ぜる'),('復習の並び順','期限順'))),('兄弟カードを埋める',rows(('新規カード','ON'),('復習カード','ON'),('翌日以降の学習カード','ON')))],back='M30')
 standard('M32A','自動送りとタイマー',[('自動送り',rows(('自動送りを使用','OFF'),('問題の表示時間','10秒'),('解答の表示時間','5秒'),('解答後の動作','普通'),('音声の終了を待つ','ON'))),('タイマー',rows(('回答時間を表示','ON'),('記録する上限','60秒'),('解答表示時に停止','ON')))],back='M30')
 standard('M33','カスタム学習',[('今日の学習を調整',rows(('新規の上限を増やす'),('復習の上限を増やす'),('今日の忘れたカードを復習'),('先の復習を予習'),('新規カードをプレビュー'))),('対象を選ぶ',rows(('状態・タグで絞って学習','','M34'),('埋めたカードを戻す','','M02')))],back='M02',section='deck')
 c=Canvas('M34','フィルターデッキ',section='deck',back='M33');x,y,w=c.x,c.y,c.cw;y=c.field(y,'検索条件','deck:英語 tag:marked',62);y=c.field(y,'2つ目のフィルター（任意）','is:due',52)
 for lab,val in [('枚数の上限','100'),('取得順','ランダム'),('学習後に再スケジュール','ON')]:y=c.row(x,y,w,lab,val)
 c.button(x,y+28,w,'デッキを作成・再構築','blue',target='M02');c.button(x,y+92,w,'カードを元のデッキに戻す','surface',target='M02');c.finish()
 standard('M35','プロフィール',[('この端末',rows(('個人','使用中'),('仕事','別のAnkiWeb'),('プロフィールを追加','','M25','plus'))),('プロフィールの管理',rows(('名前を変更'),('削除','','M44'),('切り替える')))],notice='学習履歴と同期アカウントは別々です。\nプロフィールごとにAnkiWebを設定します。',back='M20')
 standard('M36','バックアップと保守',[('自動バックアップ',rows(('今日 04:00','2,480枚','M36R'),('昨日 04:00','2,468枚','M36R'),('10月4日 04:00','2,453枚','M36R'))),('コレクションの保守',rows(('今すぐバックアップ','','M36R','shield'),('データベースをチェック','','M36D'),('メディアをチェック','','M36M'),('全体を書き出す','','M28E')))],notice='自動バックアップはカードと履歴を保存。\n音声・画像は全体の書き出しで保存できます。',back='M20')
 standard('M36R','復元の確認',[('復元する内容',rows(('バックアップ','今日 04:00'),('カード','2,480枚'),('学習履歴','04:00まで'))),('操作',rows(('現在の状態を保存して復元','','M01','shield'),('キャンセル','','M36')))],notice='端末のカードと履歴を置き換えます。\n音声と画像はこのバックアップに含まれません。',back='M36')
 standard('M36D','データベースのチェック',[('チェック結果',rows(('カードとノート','問題なし'),('未使用タグ','8件を整理'),('整合性','正常'))),('完了',rows(('バックアップと保守へ','','M36')))],notice='チェックが完了しました。\nコレクションの整合性を確認しました。',back='M36')
 standard('M36M','メディアのチェック',[('チェック結果',rows(('参照があるファイル','1,842件'),('見つからないファイル','3件'),('未使用のファイル','18件'))),('対応',rows(('不足ファイルを表示'),('メディア同期を再試行','','M24P'),('未使用ファイルを確認して削除','','M44')))],notice='削除前に対象ファイルを一覧で確認。\nカードが参照するファイルは削除しません。',back='M36')
 standard('M37','学習ツール',[('よく使う操作',rows(('編集・ノート追加','','M10','edit'),('音声・一時録音','','M39','mic'),('手書きメモ','','M38','pen'),('カード情報','','M41','stats'))),('カードとノート',rows(('フラグ・マーク・埋める・停止','','M37A'),('期限変更・新規に戻す','','M41'),('学習オプション','','M30'),('全画面・文字サイズ・夜間表示','','M21B')))],back='M03',section='deck')
 standard('M37A','カードとノート',[('カード',rows(('フラグ','なし / 1–7'),('このカードを埋める'),('このカードを停止'))),('ノート（関連カードにも適用）',rows(('マークを付ける'),('マークして埋める'),('マークして停止'),('このノートを埋める・停止'),('このノートを削除','','M44')))],back='M37',section='deck')
 c=Canvas('M38','手書きメモ',back='M03');x,y,w=c.x,c.y,c.cw;c.text(x,y,'「幸運」を書いて覚える',20,bold=True,w=w);c.card(x,y+60,w,325);c.text(x+30,y+125,'幸 運',70,color='blue',w=w-60,align='center');c.text(x+20,y+325,'手書きの内容は学習メモです',11,color='muted',w=w-40,align='center');c.button(x,y+407,w,'取り消す / すべて消去','tint',icon='undo',target='M38');c.row(x,y+479,w,'Apple Pencilのみ','ON');c.row(x,y+534,w,'メモの位置とサイズ','下 / 中');c.finish(False)
 c=Canvas('M39','音声とメディア',back='M10',section='browse');x,y,w=c.x,c.y,c.cw;c.card(x,y,w,193,'音声を録音','00:12  ·  自分の発音を聞き比べる')
 for i in range(34):hh=10+abs(math.sin(i*1.7))*40;c.rect(x+22+i*(w-44)/34,y+116-hh/2,3,hh,'blue',2)
 c.button(x,y+215,w,'録音を停止・確認','blue',icon='mic',target='M10');yy=y+292
 for label,ic in [('カメラで撮影','image'),('写真ライブラリ','image'),('ファイルから追加','folder'),('iPadで描画して添付','pen')]:yy=c.row(x,yy,w,label,icon=ic,target='M10')
 c.text(x,yy+20,'再生 / 一時停止 / ±5秒 / TTS',12,color='muted',w=w);c.finish()
 c=Canvas('M40','画像穴埋め',section='browse',back='M13');x,y,w=c.x,c.y,c.cw;c.pill(x,y,'すべて隠して1つ回答',w=226);c.card(x,y+48,w,318,'細胞のつくり');c.rect(x+80,y+122,w-160,160,'greenSoft',80,stroke='green');c.rect(x+125,y+163,w-250,74,'violetSoft',35,stroke='violet');c.rect(x+60,y+139,105,30,'orangeSoft',5,stroke='orange');c.rect(x+w-156,y+227,112,30,'tint',5,stroke='blue');c.text(x+71,y+143,'① マスク',12,w=90);c.text(x+w-145,y+231,'② マスク',12,w=94);c.text(x+20,y+320,'元画像にマスクを重ねて出題',12,color='muted',w=w-40,align='center');c.button(x,y+388,w,'四角・楕円・多角形・選択','tint',target='M40');c.row(x,y+454,w,'マスクのグループ化','2つ選択');c.button(x,y+542,w,'2枚のカードを作成','blue',target='M06');c.finish()
 standard('M41','カード情報',[('スケジュール',rows(('期限','今日'),('間隔','12日'),('復習 / 忘却','18回 / 2回'),('安定性 / 難易度','14.2日 / 42%'),('想起確率','92%'))),('履歴と操作',rows(('学習履歴を表示','18件'),('期限を設定','0 = 今日'),('新規に戻す'),('新規の位置を変更')))],back='M37',section='deck')
 standard('M42','ヘルプと外部連携',[('使い方',rows(('スタートガイド'),('Anki互換機能について'),('アクセシビリティ','VoiceOver等'))),('外部との連携',rows(('辞書アプリ・Web辞書'),('URL Schemeで追加・検索・同期'),('Shortcutsとの連携'),('MathJax・カスタムフォント'),('バージョンとライセンス')))],back='M20')
 standard('M43','デッキの管理',[('構成',rows(('名前を変更','英語・毎日のことば'),('サブデッキを作成'),('親デッキを変更','英語'),('デッキの説明を編集'))),('管理',rows(('書き出す','','M28E'),('埋めたカードを戻す','','M02'),('デッキを削除','','M44')))],back='M02',section='deck')
 c=Canvas('M44','削除の確認',back='M02');x,y,w=c.x,c.y,c.cw;c.card(x,y+95,w,290,'ノート3件を削除しますか？');c.text(x+20,y+155,'関連するカード6枚も削除されます。\n対象を確認してから実行してください。',14,color='muted',w=w-40);c.button(x+20,y+240,w-40,'削除する','redSoft',target='M06');c.button(x+20,y+302,w-40,'キャンセル','surface',target='M08');c.finish()
 c=Canvas('M45','デッキ',dark=True);decks(c);c.finish()
 c=Canvas('M46','学習',dark=True,back='M45');review(c,True);c.finish(False)
 c=Canvas('M47','デッキ');x,y,w=c.x,c.y,c.cw;c.icon(x+w/2-38,y+81,'deck',76,'blue');c.text(x,y+205,'最初のデッキを作ろう',25,bold=True,w=w,align='center');c.text(x,y+255,'自分で作る、共有デッキを探す、\nAnkiから読み込む。好きな方法で。',14,color='muted',w=w,align='center');c.button(x,y+351,w,'デッキを作成','blue',target='M43');c.button(x,y+416,w,'ファイルから読み込む','tint',target='M27');c.finish()
 c=Canvas('M48','同期できません',section='settings',back='M24');x,y,w=c.x,c.y,c.cw;c.icon(x+w/2-36,y+73,'cloud',72,'muted');c.text(x,y+192,'今はオフラインです',23,bold=True,w=w,align='center');c.text(x,y+238,'16件の変更は、この端末に保存済み。\n接続後に同期を再開できます。',14,color='muted',w=w,align='center');c.button(x,y+335,w,'もう一度試す','blue',target='M24P');c.button(x,y+400,w,'学習を続ける','tint',target='M01');c.finish()
 # iPad: true structural changes in deck, browse, editing and statistics.
 for sid,title,func,section in [('I01','デッキ',decks,'deck'),('I02','デッキの詳細',deck_detail,'deck'),('I03','学習',lambda c:review(c),'deck'),('I03A','学習',lambda c:review(c,True),'deck'),('I04','ブラウズ',browse,'browse'),('I05','統計',stats,'stats'),('I06','ノートを編集',editor,'browse'),('I07','記憶の分布',lambda c:stats(c,'advanced'),'stats'),('I08','学習と手書き',lambda c:review(c,True,scratch=True),'deck')]:c=Canvas(sid,title,1194,834,'02 iPad',section=section);func(c);c.finish(False)
 standard('I09','設定',[('学習と表示',rows(('学習画面・音声・タップ設定','','M21'),('キーボードとゲームパッド','','M23'),('テーマ・通知・一般','','M21G'))),('アカウントとデータ',rows(('AnkiWebと同期','同期済み','M24'),('プロフィール','個人','M35'),('バックアップとメンテナンス','','M36')))],w=1194,h=834,page='02 iPad',back=None)
 # Width and accessibility proofs share exactly the same screen functions.
 for sid,w,h,func,sec,title in [('R01',320,812,decks,'deck','デッキ'),('R02',430,932,decks,'deck','デッキ'),('R03',600,900,stats,'stats','統計'),('R04',744,1133,decks,'deck','デッキ'),('R05',1024,768,browse,'browse','ブラウズ'),('R07',844,390,lambda c:None,'deck','学習')]:
  c=Canvas(sid,title,w,h,'03 Adaptive',section=sec)
  if sid=='R07':
   c.nodes.clear();c.side=0;c.x=24;c.cw=w-48;c.rect(0,0,w,h,'bg');c.text(24,22,'‹  英語・毎日のことば',15,w=450);c.text(w-210,25,'12 新規  /  8 学習  /  48 復習',11,color='muted',w=190);c.card(24,74,485,238);c.text(50,129,'serendipity',35,bold=True,w=433,align='center');c.text(50,204,'思いがけない幸運',22,w=433,align='center')
   for i,(lab,tone) in enumerate([('もう一度 · 1分','redSoft'),('難しい · 6分','orangeSoft'),('普通 · 1日','greenSoft'),('簡単 · 4日','tint')]):c.button(533,74+i*61,287,lab,tone,target='M05',h=50)
   c.text(24,341,'元に戻す   /   音声   /   編集   /   ツール',12,color='muted',w=620)
  else:func(c)
  c.finish(sid!='R07')
 c=Canvas('R06','デッキ',390,1000,'03 Adaptive');x,y,w=c.x,c.y,c.cw;c.text(x,y,'文字サイズ：アクセシビリティ',17,color='muted',w=w);c.card(x,y+65,w,280);c.text(x+20,y+87,'今日の学習',25,bold=True,w=w-40);c.text(x+20,y+141,'84枚の復習',38,bold=True,w=w-40);c.text(x+20,y+216,'新規 20枚\n学習中 8枚',22,color='muted',w=w-40);c.button(x,y+369,w,'学習をはじめる','blue',target='M03',h=64);c.card(x,y+463,w,194);c.text(x+20,y+484,'英語・毎日のことば',24,bold=True,w=w-40);c.text(x+20,y+542,'復習 48枚\n新規 12枚',22,color='muted',w=w-40);c.finish()

def svg(screen):
 out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{screen["width"]}" height="{screen["height"]}" viewBox="0 0 {screen["width"]} {screen["height"]}">',f'<title>{html.escape(screen["title"])}</title>']
 for n in screen['nodes']:
  x,y,w,h=n['x'],n['y'],n['w'],n['h'];fill=n['fill'];op=n.get('opacity',1)
  if n['kind']=='rect':out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{n.get("r",0)}" fill="{fill}" opacity="{op}"'+(f' stroke="{n["stroke"]}"' if n.get('stroke') else '')+'/>')
  elif n['kind']=='icon':out.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 24 24"><path d="{n["path"]}" fill="none" stroke="{fill}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>')
  elif n['kind']=='text':
   anchor={'left':'start','center':'middle','right':'end'}[n['align']];xx=x+(w/2 if anchor=='middle' else w if anchor=='end' else 0)
   for i,line in enumerate(n['text'].split('\n')):out.append(f'<text x="{xx}" y="{y+n["size"]*1.08+i*n["size"]*1.55}" fill="{fill}" font-family="Noto Sans CJK JP, Noto Sans JP, sans-serif" font-size="{n["size"]}" font-weight="{n["weight"]}" text-anchor="{anchor}">{html.escape(line)}</text>')
 out.append('</svg>');return '\n'.join(out)

def write():
 make_screens();(ROOT/'proofs').mkdir(exist_ok=True)
 for s in SCREENS:(ROOT/'proofs'/f'{s["id"]}.svg').write_text(svg(s))
 (ROOT/'scene.json').write_text(json.dumps(dict(name='Negoto / Fresh AnkiMobile parity',version=2,checked='2026-10-06',tokens={'light':LIGHT,'dark':DARK},screens=SCREENS),ensure_ascii=False,separators=(',',':')))
 (ROOT/'screen-index.js').write_text('window.SCREEN_INDEX='+json.dumps([{k:v for k,v in s.items() if k!='nodes'} for s in SCREENS],ensure_ascii=False)+';\n')
 print(json.dumps({'screens':len(SCREENS),'nodes':sum(len(s['nodes']) for s in SCREENS),'pages':sorted(set(s['page'] for s in SCREENS))}))

if __name__=='__main__':write()
