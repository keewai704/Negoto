#!/usr/bin/env python3
"""Build editable Penpot scenes and SVG proofs. Python standard library only."""
from pathlib import Path
import copy
import html
import json
import math
import re

ROOT = Path(__file__).resolve().parent
LIGHT = dict(bg='#F5F7FB', surface='#FFFFFF', ink='#18243D', muted='#63718A',
             line='#E3E8F0', blue='#2563EB', blueSoft='#EAF1FF', green='#16815D',
             greenSoft='#E8F5EF', red='#CD4552', redSoft='#FCECEF', amber='#A96A19',
             amberSoft='#FFF3DB', purple='#785BC5', purpleSoft='#F0ECFA', navy='#182D55')
DARK = dict(bg='#101827', surface='#1A263B', ink='#F0F4FC', muted='#ACB9CE',
            line='#30405A', blue='#8BB5FF', blueSoft='#243B60', green='#7ED7AF',
            greenSoft='#193D34', red='#FF9CAA', redSoft='#492A35', amber='#F2C578',
            amberSoft='#493B28', purple='#BCA5F3', purpleSoft='#352D4C', navy='#162D50')
C = LIGHT.copy()
SCREENS = []

ICONS = {
 'deck':'M4 7h16v14H4z M7 3h10 M5 5h14 M8 11h8 M8 15h5',
 'search':'M10.5 3a7.5 7.5 0 1 0 0 15a7.5 7.5 0 1 0 0-15 M16 16l5 5',
 'chart':'M4 20V10 M10 20V4 M16 20v-7 M22 20H2',
 'settings':'M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1z M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8',
 'plus':'M12 5v14 M5 12h14', 'close':'M6 6l12 12 M18 6L6 18',
 'chevron':'M9 5l7 7-7 7', 'back':'M15 5l-7 7 7 7',
 'down':'M5 9l7 7 7-7', 'check':'M5 12l4 4L19 6',
 'sync':'M20 8a8 8 0 0 0-14-3L3 8 M3 3v5h5 M4 16a8 8 0 0 0 14 3l3-3 M21 21v-5h-5',
 'more':'M5 11v2 M12 11v2 M19 11v2',
 'audio':'M4 9h4l5-5v16l-5-5H4z M17 8a6 6 0 0 1 0 8 M20 5a10 10 0 0 1 0 14',
 'undo':'M8 4L3 9l5 5 M3 9h11a6 6 0 0 1 0 12',
 'flag':'M5 22V3h14l-3 5 3 5H5',
 'edit':'M4 17L16 5l3 3L7 20H4z M14 7l3 3 M14 21h7',
 'filter':'M3 5h18 M6 12h12 M10 19h4',
 'cloud':'M6 18a5 5 0 1 1 0-10a6 6 0 0 1 12 0a5 5 0 0 1 0 10z',
 'download':'M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5',
 'upload':'M12 16V4 M7 9l5-5 5 5 M4 16v5h16v-5',
 'clock':'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20 M12 6v6l4 2',
 'sun':'M12 7a5 5 0 1 0 0 10a5 5 0 1 0 0-10 M12 1v3 M12 20v3 M1 12h3 M20 12h3 M4 4l2 2 M18 18l2 2 M20 4l-2 2 M6 18l-2 2',
 'tag':'M3 3h8l10 10-8 8L3 11z M7 7h.1',
 'file':'M5 3h9l5 5v13H5z M14 3v6h5 M8 13h8 M8 17h6',
 'image':'M3 4h18v16H3z M3 17l6-6 4 4 3-3 5 5 M16 8h.1',
 'mic':'M9 4a3 3 0 0 1 6 0v8a3 3 0 0 1-6 0z M5 10v2a7 7 0 0 0 14 0v-2 M12 19v3 M8 22h8',
 'pencil':'M4 20l2-7L17 2l5 5-11 11z M14 5l5 5 M6 13l5 5',
 'eye':'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6',
 'box':'M3 7l9-5 9 5v11l-9 5-9-5z M3 7l9 5 9-5 M12 12v11',
 'star':'M12 2l3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z',
 'pause':'M7 4v16 M17 4v16', 'play':'M7 4l13 8-13 8z',
 'keyboard':'M2 5h20v14H2z M6 9h1 M11 9h1 M16 9h1 M6 13h1 M11 13h1 M16 13h1 M7 16h10',
 'person':'M12 3a4 4 0 1 0 0 8a4 4 0 1 0 0-8 M4 22v-3a8 8 0 0 1 16 0v3',
 'shield':'M12 2l9 4v7c0 5-9 9-9 9S3 18 3 13V6z M8 12l3 3 5-6',
 'trash':'M3 6h18 M8 6V3h8v3 M5 6l1 15h12l1-15 M9 10v7 M15 10v7',
 'info':'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20 M12 11v6 M12 7v1',
}

def add(p, kind, x, y, w, h, name='', **kw):
    n=dict(type=kind, x=round(x,2), y=round(y,2), w=round(w,2), h=round(h,2), name=name or kind, **kw)
    p.setdefault('children', []).append(n)
    return n

def panel(p,x,y,w,h,fill=None,r=18,name='Surface',stroke=None,layout=None):
    return add(p,'board',x,y,w,h,name,fill=fill or C['surface'],radius=r,stroke=stroke,children=[],layout=layout)

def rect(p,x,y,w,h,fill,r=0,name='Shape'):
    return add(p,'rect',x,y,w,h,name,fill=fill,radius=r)

def text(p,s,x,y,w,size=15,color=None,weight=400,h=None,align='left',name=None):
    if not s:return None
    return add(p,'text',x,y,w,h or math.ceil(size*1.55)*(s.count('\n')+1),name or s[:45],text=s,size=size,color=color or C['ink'],weight=weight,align=align)

def icon(p,key,x,y,size=22,color=None):
    return add(p,'icon',x,y,size,size,key,path=ICONS[key],color=color or C['muted'])

def rule(p,x,y,w): return rect(p,x,y,w,1,C['line'])

def hit(p,x,y,w,h,target,label):
    return add(p,'hit',x,y,w,h,'→ '+label,target=target)

def button(p,label,x,y,w,target=None,style='primary',h=48,ico=None):
    fill=C['blue'] if style=='primary' else C['redSoft'] if style=='danger' else C['blueSoft'] if style=='soft' else C['surface']
    color=('#142440' if C is DARK else '#FFFFFF') if style=='primary' else C['red'] if style=='danger' else C['blue']
    # Button content is a genuine Penpot flex layout, not a flattened image.
    b=panel(p,x,y,w,h,fill,13,'Button / '+label,layout=dict(dir='row',alignItems='center',justifyContent='center',gap=8))
    if ico: icon(b,ico,14,(h-20)/2,20,color)
    text(b,label,10 if not ico else 40,(h-24)/2,w-20 if not ico else w-54,15,color,600,h=24,align='center')
    if target: hit(p,x,y,w,h,target,label)
    return b

def ib(p,key,x,y,target=None,color=None):
    b=panel(p,x,y,44,44,C['surface'],14,'Icon button / '+key)
    icon(b,key,11,11,22,color or C['blue'])
    if target: hit(p,x,y,44,44,target,key)
    return b

def chip(p,label,x,y,w=None,selected=False,target=None,color=None):
    w=w or max(56,len(label)*12+24)
    rect(p,x,y,w,32,C['blueSoft'] if selected else C['surface'],10)
    text(p,label,x+8,y+5,w-16,12,color or (C['blue'] if selected else C['muted']),600 if selected else 500,align='center')
    if target: hit(p,x,y-6,w,44,target,label)

def badge(p,label,x,y,w,color='blue'):
    rect(p,x,y,w,24,C[color+'Soft'],7)
    text(p,label,x+6,y+3,w-12,11,C[color],600,align='center')

def toggle(p,x,y,on=True):
    rect(p,x,y,44,27,C['green'] if on else C['line'],14)
    add(p,'ellipse',x+(20 if on else 3),y+3,21,21,'Switch / '+str(on),fill='#FFFFFF')

def row(p,title,y,value='',sub=None,ico=None,target=None,on=None,color=None,h=64):
    w=p['w']; left=18
    if ico:
        rect(p,16,y+14,34,34,C['blueSoft'],10);icon(p,ico,23,y+21,20,C['blue']);left=62
    size=14 if len(title)>16 else 15
    text(p,title,left,y+(10 if sub else 20),w-left-80,size,color,500)
    if sub: text(p,sub,left,y+35,w-left-24,11,C['muted'])
    if value: text(p,value,max(left+100,w-151),y+20,116,13,C['muted'],align='right')
    if on is not None: toggle(p,w-62,y+18,on)
    elif target: icon(p,'chevron',w-28,y+24,15)
    if target: hit(p,0,y,w,h,target,title)
    rule(p,left,y+h-1,w-left-16)

def label(p,s,x,y,w=320): text(p,s,x,y,w,12,C['muted'],600)

def section(p,title,x,y,w):
    text(p,title,x,y,w,18,weight=650)

def note(p,s,x,y,w,h=60,color='blue'):
    b=panel(p,x,y,w,h,C[color+'Soft'],12,'Context / '+s[:24])
    icon(b,'info',14,15,18,C[color]);text(b,s,43,12,w-56,12,C[color],h=h-20)
    return b

PRODUCT_PAGE='01 Product · iPhone & iPad'

def screen(key,title,page=PRODUCT_PAGE,w=393,h=852,tab='deck',sub='',back=None,action=None):
    s=dict(key=key,title=title,name=key+' · '+title,page=page,w=w,h=h,fill=C['bg'],children=[],theme='dark' if C is DARK else 'light')
    SCREENS.append(s)
    # Status area and home indicator are display elements, not app hit targets.
    text(s,'9:41',25,14,65,14,weight=650)
    rect(s,w-73,21,17,9,C['ink'],2);rect(s,w-50,19,25,12,C['ink'],3);rect(s,w-47,22,18,6,C['surface'],1)
    if back:
        icon(s,'back',18,69,20,C['blue']);hit(s,8,56,44,44,back,'戻る')
        text(s,title,49,62,w-110,21,weight=700)
    else: text(s,title,22,63,w-85,min(29,(w-85)/max(1,len(title))),weight=700)
    if sub:text(s,sub,24,109,w-48,12,C['muted'])
    if action: ib(s,action[0],w-66,58,action[1])
    if tab: tabs(s,tab)
    rect(s,w/2-60,h-13,120,4,C['ink'],2,'Home indicator')
    return s

def tabs(s,active):
    w=s['w'];y=s['h']-92
    bar=panel(s,0,y,w,92,C['surface'],0,'Navigation / Compact tab bar')
    rule(bar,0,0,w)
    for i,(ico,title,target) in enumerate([('deck','デッキ','M01'),('search','ブラウズ','M10'),('chart','統計','M20'),('settings','設定','M30')]):
        cx=(i+.5)*w/4
        if ico==active:rect(bar,cx-29,8,58,33,C['blueSoft'],13)
        icon(bar,ico,cx-11,14,22,C['blue'] if ico==active else C['muted'])
        text(bar,title,cx-w/8,43,w/4,10,C['blue'] if ico==active else C['muted'],600,align='center')
        hit(bar,cx-w/8,3,w/4,65,target,title)

def progress(p,x,y,w,value,color=None):
    rect(p,x,y,w,5,C['line'],3);rect(p,x,y,w*value,5,color or C['blue'],3)

def decklist(p,x,y,w):
    b=panel(p,x,y,w,234,name='Deck list')
    data=[('英語 / Everyday English','1,240 枚',12,4,24,'blue'),('日本語 / 表現を広げる','860 枚',5,3,12,'purple'),('医学 / 基礎をおさらい','1,100 枚',3,1,8,'green')]
    for i,(title,sub,n,l,r,c) in enumerate(data):
        yy=i*78;rect(b,16,yy+18,38,42,C[c+'Soft'],10);icon(b,'deck',24,yy+27,22,C[c])
        text(b,title,66,yy+16,w-88,13,weight=600);text(b,sub,66,yy+42,105,11,C['muted'])
        text(b,str(n),w-127,yy+42,29,12,C['blue'],650,align='right')
        text(b,str(l),w-85,yy+42,22,12,C['red'],650,align='right')
        text(b,str(r),w-51,yy+42,30,12,C['green'],650,align='right')
        if i<2:rule(b,66,yy+77,w-82)
        hit(b,0,yy,w,78,'M02',title)
    return b

def bars(p,x,y,w,h,values,color=None,labels=None):
    col=color or C['blue'];gap=7;bw=(w-gap*(len(values)-1))/len(values)
    for fraction in [0,.5,1]:
        rect(p,x,y+h*fraction,w,1,C['line'])
    top=max(values) or 1
    for i,v in enumerate(values):
        bh=max(3,h*v/top)
        rect(p,x+i*(bw+gap),y+h-bh,bw,bh,col if i==len(values)-1 else C['blueSoft'] if col==C['blue'] else col,4)
        if labels:text(p,labels[i],x+i*(bw+gap)-5,y+h+8,bw+10,10,C['muted'],align='center')

def chartcard(p,x,y,w,h,title,metric,values,sub='',color=None):
    b=panel(p,x,y,w,h,name='Chart / '+title)
    text(b,title,18,15,w-36,14,weight=600);text(b,metric,18,44,w-36,28,weight=700)
    if sub:text(b,sub,18,84,w-36,11,C['muted'])
    bars(b,20,118,w-40,h-155,values,color)
    endpoints=('10/6','10/12') if 'これから' in title else ('1日','365日') if '間隔' in title else ('0日','180日') if '安定度' in title else ('1','10') if '難易度' in title else ('0%','100%') if '想起確率' in title else ('130%','350%') if 'Ease' in title else ('0時','23時') if '時間帯' in title else ('1日後','365日後') if '1年' in title else ('9/7','10/6')
    text(b,endpoints[0],20,h-26,75,10,C['muted']);text(b,endpoints[1],w-96,h-26,76,10,C['muted'],align='right')
    return b

def heatmap(p,x,y,w,rows=7,cols=15):
    gap=4;sz=(w-gap*(cols-1))/cols
    for cx in range(cols):
        for cy in range(rows):
            intensity=(cx*7+cy*3+cx*cy)%10
            fill=C['line'] if intensity<2 else C['blueSoft'] if intensity<5 else '#A6C3FF' if intensity<8 else C['blue']
            rect(p,x+cx*(sz+gap),y+cy*(sz+gap),sz,sz,fill,3)

def build_primary():
    s=screen('M01','今日の学習',sub='10月6日 火曜日',action=('plus','M03'))
    b=panel(s,20,148,353,220,C['navy'],22,'Today / Learning focus')
    text(b,'少しずつ、確かな記憶に。',20,17,310,14,'#CFDCF5',500)
    text(b,'72',20,46,146,58,'#FFFFFF',700);text(b,'枚 残っています',113,77,210,15,'#CFDCF5')
    text(b,'新規 20     学習中 8     復習 44',20,119,315,12,'#CFDCF5')
    button(b,'学習をはじめる',20,158,313,'M04',h=46,ico='play')
    text(s,'今日の進み具合',22,389,195,12,C['muted']);text(s,'128 / 200 枚',236,389,134,12,C['ink'],600,align='right')
    progress(s,22,421,349,.64)
    section(s,'マイデッキ',22,445,240);ib(s,'search',331,434,'M10')
    decklist(s,20,486,353)
    s=screen('M02','Everyday English',back='M01',tab=None,action=('more','M03'))
    badge(s,'ENGLISH',22,116,80)
    text(s,'毎日の英語を、自分の言葉に。',22,158,349,17,weight=600)
    text(s,'日常会話・表現集  /  1,240 枚',22,194,349,12,C['muted'])
    b=panel(s,20,234,353,110,name='Deck / Due counts')
    for i,(v,l,c) in enumerate([('12','新規','blue'),('4','学習中','red'),('24','復習','green')]):
        text(b,v,16+i*114,14,92,32,C[c],700,align='center');text(b,l,16+i*114,67,92,12,C['muted'],align='center')
    button(s,'40枚を学習する',20,366,353,'M04',ico='play')
    button(s,'カスタム学習',20,428,170,'M34',style='soft');button(s,'オプション',202,428,171,'M31',style='soft')
    b=panel(s,20,501,353,203,name='Deck / Upcoming')
    text(b,'これからの7日間',18,16,270,15,weight=600)
    bars(b,20,65,313,89,[24,18,31,22,38,12,20],C['green'],['火','水','木','金','土','日','月'])
    button(s,'デッキの統計を見る',20,723,353,'M20',style='plain')
    s=screen('M03','デッキを管理',back='M01',tab=None)
    b=panel(s,20,132,353,320,name='Deck / Actions')
    for i,(t,ico,target) in enumerate([('デッキを作成','plus','M46'),('カードを追加','edit','M13'),('ファイルを読み込む','download','M38'),('共有デッキを探す','cloud','M47'),('フィルタデッキを作成','filter','M35')]): row(b,t,i*64,ico=ico,target=target)
    label(s,'このデッキ',24,478)
    b=panel(s,20,510,353,192)
    row(b,'名前・親デッキを変更',0,target='M46');row(b,'デッキを書き出す',64,target='M40');row(b,'デッキを削除',128,target='M67',color=C['red'])
    for key,answer in [('M04',False),('M05',True)]:
        s=screen(key,'',tab=None)
        s['title']='学習 / 答え' if answer else '学習 / 問い';s['name']=key+' · '+s['title']
        ib(s,'close',14,56,'M02');ib(s,'undo',287,56,'M04');ib(s,'more',337,56,'M07')
        text(s,'12     4     24',104,66,180,17,weight=650,align='center');rect(s,228,96,27,3,C['green'],2)
        text(s,'EVERYDAY ENGLISH',26,131,341,11,C['muted'],600,align='center')
        b=panel(s,20,175,353,466,name='Study / Card')
        badge(b,'表現',145,30,64,'purple');text(b,'こもれび',20,92,313,14,C['muted'],align='center')
        text(b,'木漏れ日',20,125,313,40,weight=650,align='center')
        text(b,'この言葉を英語で説明してみましょう。',20,200,313,12,C['muted'],align='center')
        if answer:
            rule(b,32,249,289);text(b,'sunlight filtering\nthrough trees',23,273,307,18,weight=600,h=60,align='center')
            text(b,'The forest floor glowed with\nsunlight filtering through the leaves.',23,343,307,12,C['muted'],h=43,align='center')
            ib(b,'audio',155,402,'M07')
        else:
            icon(b,'audio',165,313,24,C['blue']);text(b,'音声を再生',26,355,301,12,C['blue'],align='center')
        text(s,'あと約 8 分  ·  3 / 40',23,663,347,12,C['muted'],align='center')
        if answer:
            for i,(t,iv,c) in enumerate([('もう一度','1分','red'),('難しい','6日','amber'),('普通','12日','green'),('簡単','24日','blue')]):
                x=20+i*91;text(s,iv,x,704,80,11,C['muted'],align='center')
                b=panel(s,x,730,80,52,C[c+'Soft'],13,'Rating / '+t);text(b,t,3,16,74,13,C[c],600,align='center');hit(s,x,730,80,52,'M09',t)
        else:button(s,'答えを表示',20,726,353,'M05',h=56)
    s=screen('M06','入力して答える',back='M04',tab=None)
    b=panel(s,20,140,353,310);badge(b,'入力式',140,25,73)
    text(b,'「継続は力なり」',20,103,313,26,weight=650,align='center');text(b,'英語で入力してください',20,164,313,13,C['muted'],align='center')
    b=panel(s,20,476,353,62,stroke=C['blue']);text(b,'Practice makes perfect.',17,20,318,16)
    note(s,'答えを表示すると、入力した文字と\n正解の違いを確認できます。',20,560,353,70)
    button(s,'入力した答えを確認',20,724,353,'M49')
    s=screen('M07','学習ツール',back='M05',tab=None,h=1110)
    for i,(ico,title,target) in enumerate([('edit','ノートを編集','M13'),('info','カード情報','M08'),('pencil','手書きパッド','M50')]):
        b=panel(s,20+i*122,127,109,88);icon(b,ico,43,13,23,C['blue']);text(b,title,5,51,99,11,weight=500,align='center');hit(b,0,0,109,88,target,title)
    label(s,'カードとノート',24,240);b=panel(s,20,270,353,384)
    for i,(t,v,tg) in enumerate([('フラグを付ける','7色','M12'),('ノートをマーク','★','M12'),('カード／ノートを延期','明日まで','M51'),('カード／ノートを保留','解除まで','M51'),('期日を指定・新規に戻す','','M17'),('テンプレートを編集','','M16')]):row(b,t,i*64,v,target=tg)
    label(s,'音声と表示',24,681);b=panel(s,20,711,353,256)
    row(b,'再生・一時停止・±5秒',0,ico='audio',target='M52');row(b,'録音して聞き比べる',64,ico='mic',target='M52');row(b,'自動送り・文字サイズ',128,ico='play',target='M44');row(b,'カスタムアクション 1〜8',192,ico='settings',target='M44')
    button(s,'ノートを削除',20,995,353,'M48',style='danger')
    s=screen('M08','カード情報',back='M05',tab=None,h=980)
    text(s,'木漏れ日',24,131,340,26,weight=650);text(s,'カード 1  /  英語・日本語',24,172,340,12,C['muted'])
    b=panel(s,20,212,353,320)
    for i,(t,v) in enumerate([('次回の復習','10月18日'),('間隔 / 復習回数','12日 / 18回'),('忘れた回数','2回'),('安定度 / 難易度','18.2日 / 4.8'),('想起確率','92.6%')]):row(b,t,i*64,v)
    section(s,'復習履歴',24,563,320);b=panel(s,20,606,353,256)
    for i,(t,v) in enumerate([('10/6   普通','12日 · 8秒'),('9/24   普通','10日 · 6秒'),('9/14   もう一度','1分 · 11秒'),('9/14   普通','3日 · 9秒')]):row(b,t,i*64,v)
    chip(s,'日常表現',24,893,90,selected=True);chip(s,'自然',123,893,64)
    s=screen('M09','今日も、おつかれさま。',tab=None)
    add(s,'ellipse',145,153,103,103,'Complete / seal',fill=C['greenSoft']);icon(s,'check',178,186,38,C['green'])
    text(s,'ひとつ、記憶が育ちました。',20,290,353,22,weight=650,align='center')
    text(s,'Everyday English の学習が完了しました',20,337,353,12,C['muted'],align='center')
    b=panel(s,20,398,353,156)
    for i,(v,l) in enumerate([('40','学習した枚数'),('8分','学習時間'),('91%','正答率')]):text(b,v,12+i*114,29,100,28,weight=700,align='center');text(b,l,12+i*114,91,100,11,C['muted'],align='center')
    button(s,'統計を振り返る',20,604,353,'M20',style='soft');button(s,'デッキに戻る',20,671,353,'M01')

def editor(p,x,y,w,h,preview=False):
    b=panel(p,x,y,w,h,name='Note / Editor')
    text(b,'表面',18,14,w-36,12,C['muted'],600);text(b,'木漏れ日',18,49,w-36,25,weight=600)
    rule(b,18,103,w-36);text(b,'裏面',18,123,w-36,12,C['muted'],600)
    text(b,'sunlight filtering through trees',18,159,w-36,16,h=57)
    text(b,'The forest floor glowed with sunlight\nfiltering through the leaves.',18,230,w-36,13,C['muted'],h=64)
    rule(b,18,308,w-36);text(b,'音声',18,327,150,12,C['muted'],600)
    rect(b,18,359,w-36,48,C['bg'],10);icon(b,'audio',30,372,20,C['blue']);text(b,'komorebi.mp3',61,373,w-96,13)
    if h>455:
        rule(b,18,428,w-36);label(b,'タグ',18,446,w-36)
        chip(b,'日常表現',18,478,90,True,target='M18');chip(b,'自然',120,478,64,True,target='M18')
    return b

def build_library():
    s=screen('M10','ブラウズ',tab='search',sub='3,200 枚のカード',action=('plus','M13'))
    b=panel(s,20,145,300,46);icon(b,'search',13,13,20);text(b,'deck:English is:due',42,13,239,13);hit(b,0,0,300,46,'M11','検索フィルタ')
    ib(s,'filter',329,146,'M11')
    chip(s,'復習待ち',20,207,96,True,'M11');chip(s,'タグ',124,207,70,target='M18');chip(s,'選択',301,207,72,target='M12')
    text(s,'24件  ·  期日の早い順',24,265,320,12,C['muted'])
    b=panel(s,20,300,353,424,name='Browser / Card results')
    for i,(word,en,state) in enumerate([('木漏れ日','sunlight filtering through trees','今日'),('一期一会','once-in-a-lifetime encounter','今日'),('懐かしい','nostalgic','今日'),('いただきます','gratitude before a meal','明日'),('おつかれさま','thank you for your hard work','10/8')]):
        yy=i*84; text(b,word,18,yy+13,242,16,weight=600);text(b,en,18,yy+44,270,11,C['muted']);badge(b,state,284,yy+18,53,'green');rule(b,18,yy+83,317);hit(b,0,yy,353,84,'M13',word)
    s=screen('M11','検索とフィルタ',back='M10',tab=None)
    b=panel(s,20,127,353,76,stroke=C['blue']);text(b,'deck:English is:due -is:suspended',16,22,321,13)
    label(s,'条件を追加',24,227)
    b=panel(s,20,258,353,320)
    for i,(t,v,tg) in enumerate([('デッキ','English','M02'),('状態','復習待ち','M12'),('タグ','すべて','M18'),('フラグ','すべて','M12'),('並び順 / 表示列','期日','M10')]):row(b,t,i*64,v,target=tg)
    note(s,'deck:  tag:  is:  prop:  rated:  added:\nAND / OR / 除外で条件を組み合わせ',20,602,353,68)
    button(s,'検索を保存',20,691,170,'M18',style='soft');button(s,'24件を表示',202,691,171,'M10')
    s=screen('M12','一括操作',back='M10',tab=None,h=1010)
    badge(s,'12枚を選択中',24,122,114);text(s,'同じノートから作られたカードも確認',24,162,345,12,C['muted'])
    b=panel(s,20,206,353,576)
    for i,(t,v,tg) in enumerate([('デッキを変更','','M46'),('ノートタイプを変更','対応付け','M56'),('タグを追加・削除','','M18'),('フラグ・マーク','','M18'),('保留 / 保留解除','','M51'),('延期 / 延期解除','','M51'),('期日・新規位置・リセット','','M17'),('検索と置換','','M57'),('ノートを削除','12ノート','M48')]):row(b,t,i*64,v,target=tg,color=C['red'] if i==8 else None)
    note(s,'カード単位とノート単位の操作は、\n実行前に対象件数を表示します。',20,812,353,68)
    button(s,'選択を解除',20,905,353,'M10',style='soft')
    s=screen('M13','ノートを編集',back='M10',tab=None,h=1030,action=('eye','M58'))
    chip(s,'基本（表裏）',20,127,162,True,'M15');chip(s,'English',196,127,177,target='M46')
    editor(s,20,184,353,545)
    b=panel(s,20,744,353,50,name='Editor / Formatting toolbar')
    for i,(label_,tg) in enumerate([('B','M13'),('I','M13'),('U','M13'),('[…]','M13'),('ƒx','M58'),('</>','M16')]):
        text(b,label_,i*57+5,12,54,16,C['blue'],600,align='center');hit(b,i*57,0,57,50,tg,label_)
    button(s,'画像・録音・手書きを添付',20,808,353,'M59',style='soft',ico='image')
    text(s,'変更内容は保存するまで反映されません',20,877,353,11,C['muted'],align='center')
    button(s,'変更を保存',20,917,353,'M10')
    s=screen('M14','画像穴埋め',back='M13',tab=None)
    chip(s,'すべて隠して1つ回答',20,124,191,True);chip(s,'1つずつ隠す',223,124,150)
    b=panel(s,20,180,353,382,name='Image occlusion / Editable masks')
    text(b,'植物のつくり',20,20,313,17,weight=600,align='center')
    # Diagram uses editable vectors; occlusion rectangles remain separate objects.
    add(b,'icon',111,87,134,193,'Plant / stem',path='M12 22V2 M12 14C2 14 2 8 12 10 M12 9C22 9 22 3 12 5 M12 18l-4 4 M12 18l4 4',color=C['green'])
    rect(b,206,142,94,35,C['amberSoft'],7,'Mask 1 / leaf');text(b,'1',211,148,84,14,C['amber'],600,align='center')
    rect(b,52,227,76,35,C['blueSoft'],7,'Mask 2 / stem');text(b,'2',55,233,70,14,C['blue'],600,align='center')
    rect(b,210,284,77,35,C['blueSoft'],7,'Mask 3 / root');text(b,'3',214,290,69,14,C['blue'],600,align='center')
    b=panel(s,20,582,353,58)
    for i,k in enumerate(['image','box','edit','undo','trash']):icon(b,k,25+i*67,18,22,C['blue'])
    text(s,'3つのマスク  ·  3枚のカードを作成',20,668,353,13,C['muted'],align='center')
    button(s,'カードを作成',20,724,353,'M10')
    s=screen('M15','ノートタイプ',back='M13',tab=None,action=('plus','M19'))
    label(s,'コレクションのノートタイプ',24,127);b=panel(s,20,163,353,320)
    for i,(t,v,tg) in enumerate([('基本','1枚','M19'),('基本（表裏）','2枚','M19'),('穴埋め','Cloze','M19'),('画像穴埋め','Image Occlusion','M14'),('入力式','Type-in','M19')]):row(b,t,i*64,v,target=tg)
    note(s,'ノートタイプごとにフィールドと\nカードテンプレートを管理できます。',20,511,353,70)
    button(s,'複製して作成',20,610,353,'M19',style='soft')
    s=screen('M16','カードテンプレート',back='M15',tab=None,h=1050)
    chip(s,'表面',20,126,105,True);chip(s,'裏面',144,126,105);chip(s,'CSS',268,126,105)
    b=panel(s,20,185,353,322,C['navy'],16,'Template / Code')
    text(b,'01   <div class="word">\n02     {{Front}}\n03   </div>\n04   {{#Audio}}\n05     {{Audio}}\n06   {{/Audio}}\n07\n08   {{hint:Example}}\n09   {{tts ja_JP:Front}}',17,20,321,13,'#DDE7FF',h=275)
    chip(s,'フィールドを挿入',20,528,166,target='M19');chip(s,'カード1 / 表裏',198,528,175,target='M15')
    section(s,'ライブプレビュー',24,590,330)
    b=panel(s,20,632,353,190);text(b,'木漏れ日',20,45,313,32,weight=600,align='center');text(b,'例文を見る',20,112,313,13,C['blue'],align='center')
    text(s,'HTML / CSS / JS · MathJax · TTS · 条件付き表示',20,846,353,11,C['muted'],align='center')
    button(s,'テンプレートを保存',20,915,353,'M15')
    s=screen('M17','スケジュールを変更',back='M12',tab=None)
    badge(s,'12枚のカード',24,125,115)
    b=panel(s,20,174,353,192);row(b,'期日を指定',0,'7〜14 日',target='M17');row(b,'新規カードの順番',64,'先頭 1 / 間隔 1',target='M17');row(b,'新規カードに戻す',128,target='M17')
    note(s,'期日を7〜14日の範囲に分散します。\n変更後も過去の復習履歴は保持されます。',20,397,353,78)
    b=panel(s,20,504,353,128);row(b,'復習間隔も更新する',0,on=False);row(b,'復習・忘却回数をリセット',64,on=False)
    button(s,'12枚に適用する',20,724,353,'M10')
    s=screen('M18','タグと保存した検索',back='M10',tab=None,action=('plus','M18'))
    b=panel(s,20,130,353,256)
    for i,(t,v) in enumerate([('日常表現','342'),('  自然','68'),('  感情','124'),('marked','32')]):row(b,t,i*64,v,target='M10')
    label(s,'保存した検索',24,418);b=panel(s,20,452,353,192)
    row(b,'今日忘れたカード',0,sub='rated:1:1',target='M10');row(b,'苦手なカード',64,sub='tag:leech',target='M10');row(b,'最近追加したカード',128,sub='added:7',target='M10')
    text(s,'長押しで名前変更・削除・階層の移動',24,680,345,12,C['muted'])
    s=screen('M19','フィールドを管理',back='M15',tab=None)
    badge(s,'基本（表裏）',24,126,116);b=panel(s,20,177,353,256)
    for i,(t,v) in enumerate([('Front','必須 · 並び順の基準'),('Back',''),('Example',''),('Audio','')]):row(b,t,i*64,v,target='M13')
    button(s,'フィールドを追加',20,458,353,'M19',style='soft')
    b=panel(s,20,536,353,128);row(b,'編集中の文字サイズ',0,'18 pt');row(b,'右から左に表示',64,on=False)
    button(s,'カードテンプレート',20,714,353,'M16')

def statnav(s,active):
    chip(s,'全デッキ',20,125,118,True,'M02');chip(s,'過去1か月',151,125,135,True);ib(s,'upload',329,119,'M40')
    items=[('概要','M20'),('履歴','M21'),('記憶','M22'),('保持率','M23')]
    for i,(t,tg) in enumerate(items):chip(s,t,20+i*90,176,83,active==tg,tg)

def build_stats():
    page='01 iPhone · 学習と管理'
    s=screen('M20','統計',tab='chart',h=1250);statnav(s,'M20')
    b=panel(s,20,235,353,164,name='Statistics / Today')
    text(b,'今日の積み重ね',18,17,300,14,weight=600)
    text(b,'128',18,48,195,46,weight=700);text(b,'回の回答',117,74,122,13,C['muted'])
    text(b,'18分 24秒',18,118,165,16,weight=600);badge(b,'正答率 92%',224,120,109,'green')
    b=panel(s,20,416,353,231,name='Statistics / Calendar')
    text(b,'学習カレンダー',18,16,240,14,weight=600);badge(b,'24日継続',251,14,84)
    text(b,'7月             8月             9月            10月',18,54,317,10,C['muted'])
    heatmap(b,18,80,317,7,20)
    text(b,'少ない',18,202,60,10,C['muted']);text(b,'多い',282,202,51,10,C['muted'],align='right')
    chartcard(s,20,665,353,263,'これからの復習','304 枚',[44,38,56,32,47,35,52],sub='今後7日間  ·  1日平均 43.4枚',color=C['green'])
    b=panel(s,20,946,353,148,name='Statistics / Card states')
    text(b,'コレクションの内訳',18,14,315,14,weight=600)
    vals=[(1660,'green'),(780,'blue'),(620,'purple'),(140,'amber')];xx=18
    for v,c in vals:ww=317*v/3200;rect(b,xx,58,ww-2,16,C[c],3);xx+=ww
    text(b,'成熟 1,660  ·  未成熟 780',18,92,317,12,C['muted']);text(b,'未学習 620  ·  保留ほか 140',18,115,317,12,C['muted'])
    s=screen('M21','学習の履歴',tab='chart',h=1360);statnav(s,'M21')
    chartcard(s,20,235,353,270,'復習回数','3,842 回',[80,97,123,66,141,127,160,114,133,96,128,143,168,128],sub='新規・学習・再学習・未成熟・成熟・フィルタ')
    chartcard(s,20,523,353,270,'学習時間','8時間 42分',[12,16,23,14,25,20,21,14,21,17,15,22,29,18],sub='1日平均 17.4分  ·  8.2秒 / 回')
    b=panel(s,20,811,353,232,name='Statistics / Answer ratings')
    text(b,'回答ボタンの割合',18,18,310,15,weight=600)
    for i,(t,v,c) in enumerate([('もう一度',8,'red'),('難しい',12,'amber'),('普通',67,'green'),('簡単',13,'blue')]):
        yy=60+i*38;text(b,t,18,yy,83,12);rect(b,103,yy+6,180,12,C['bg'],3);rect(b,103,yy+6,180*v/100,12,C[c],3);text(b,str(v)+'%',293,yy,43,12,C['muted'],align='right')
    b=panel(s,20,1061,353,128);row(b,'時間帯別の正答率',0,ico='clock',target='M24');row(b,'グラフの詳細・データ表',64,ico='chart',target='M25')
    s=screen('M22','記憶の状態',tab='chart',h=1530);statnav(s,'M22')
    note(s,'FSRSの記憶モデルから計算しています。\n成熟カード：復習間隔が21日以上',20,235,353,72)
    for y,title,metric,values,sub in [
        (325,'復習間隔','中央値 24日',[21,68,110,148,87,45,23,14],'横軸：間隔（日） / 縦軸：カード数'),
        (600,'安定度','平均 32.4日',[12,41,95,134,108,66,31,19],'想起確率が90%になるまでの日数'),
        (875,'難易度','平均 4.8',[16,40,95,132,156,110,85,42,19,8],'横軸：難易度 1〜10 / 縦軸：カード数')]:chartcard(s,20,y,353,255,title,metric,values,sub)
    b=panel(s,20,1148,353,212);text(b,'想起確率',18,17,310,15,weight=600);text(b,'92.6%',18,52,310,38,C['blue'],700);text(b,'今、思い出せると推定されるカード',18,118,317,12,C['muted']);text(b,'2,259 / 2,440 枚',18,151,317,22,weight=650)
    s=screen('M23','実際の保持率',tab='chart',h=1030);statnav(s,'M23')
    b=panel(s,20,235,353,171);text(b,'過去1か月',18,17,315,13,C['muted']);text(b,'91.8%',18,44,317,46,C['green'],700);text(b,'目標 90%  ·  成功 1,836 / 2,000回',18,119,317,12,C['muted'])
    b=panel(s,20,427,353,295,name='Statistics / True retention table')
    for x,t,w in [(17,'期間',99),(113,'未成熟',76),(201,'成熟',64),(272,'全体',62)]:text(b,t,x,18,w,11,C['muted'],600)
    for i,vals in enumerate([['今日','89.4%','94.2%','92.0%'],['昨日','88.8%','95.1%','92.8%'],['1週間','89.9%','93.8%','91.9%'],['1か月','88.7%','93.4%','91.8%'],['1年','88.2%','92.9%','90.6%']]):
        yy=61+i*44;rule(b,17,yy-4,319)
        for j,t in enumerate(vals):text(b,t,[17,113,201,272][j],yy,[90,76,64,65][j],12,weight=500)
    note(s,'各カードの1日最初の復習を集計。\n「もう一度」は失敗、それ以外は成功です。',20,742,353,74)
    button(s,'FSRSの目標保持率を調整',20,843,353,'M32',style='soft')
    s=screen('M24','時間帯別',back='M21',tab='chart',h=980)
    chartcard(s,20,132,353,305,'時間帯別の回答数','朝に、少しずつ。',[3,2,1,1,4,20,48,62,25,15,22,34],sub='横軸：0〜23時 / 棒：回答数',color=C['blue'])
    b=panel(s,20,460,353,256)
    row(b,'6〜9時',0,'94% · 840回');row(b,'9〜12時',64,'91% · 620回');row(b,'12〜18時',128,'92% · 1,242回');row(b,'18〜24時',192,'88% · 1,140回')
    note(s,'回答数の少ない時間帯は、\n正答率が大きく変動することがあります。',20,741,353,72)
    s=screen('M25','復習予定の詳細',back='M20',tab='chart')
    badge(s,'10月9日 金曜日',24,130,138);text(s,'32枚',24,182,345,38,weight=700)
    b=panel(s,20,267,353,192);row(b,'Everyday English',0,'18 枚');row(b,'日本語 / 表現',64,'8 枚');row(b,'医学 / 基礎',128,'6 枚')
    note(s,'期日超過は別に集計しています。\n予測は今後の回答・新規学習で変わります。',20,485,353,74)
    button(s,'該当カードをブラウズ',20,602,353,'M10',style='soft')
    s=screen('M26','SM-2 の統計',back='M22',tab='chart',h=1070)
    badge(s,'SM-2 プリセット',24,128,142)
    chartcard(s,20,176,353,285,'易しさ（Ease）','平均 248%',[4,12,33,67,110,91,52,26],sub='横軸：Ease 130〜350% / 縦軸：カード数')
    chartcard(s,20,480,353,285,'復習間隔','平均 31日',[90,112,95,76,45,22,16,12],sub='横軸：間隔（日） / 縦軸：カード数')
    note(s,'FSRSが無効のデッキでは、\n安定度・難易度・想起確率の代わりに表示。',20,787,353,75)

def form_screen(key,title,groups,back='M30',footer=None,h=None,tab=None):
    needed=142+sum(39+len(rows)*64+25 for _,rows in groups)+(95 if footer else 35)+(92 if tab else 0)
    s=screen(key,title,back=back,tab=tab,h=h or max(852,needed))
    y=130
    for title,rows in groups:
        label(s,title,24,y);y+=33
        b=panel(s,20,y,353,len(rows)*64,name=title)
        for i,r in enumerate(rows):
            t=r[0];v=r[1] if len(r)>1 else '';tg=r[2] if len(r)>2 else None
            row(b,t,i*64,'' if isinstance(v,bool) else v,target=tg,on=v if isinstance(v,bool) else None)
        y+=len(rows)*64+31
    if footer:button(s,footer[0],20,y+3,353,footer[1])
    return s

def build_settings():
    s=screen('M30','設定',tab='settings',h=1240)
    b=panel(s,20,129,353,87,name='Settings / Profile');rect(b,16,16,53,53,C['blueSoft'],17);icon(b,'person',30,29,25,C['blue']);text(b,'自分の学習',85,15,213,17,weight=600);text(b,'AnkiWeb と同期済み · たった今',85,46,240,11,C['muted']);hit(b,0,0,353,87,'M42','プロフィール')
    label(s,'学習',24,245);b=panel(s,20,277,353,256)
    for i,(t,ico,tg) in enumerate([('デッキオプション','deck','M31'),('操作・音声・自動送り','play','M44'),('表示とアクセシビリティ','sun','M45'),('リマインダー','clock','M53')]):row(b,t,i*64,ico=ico,target=tg)
    label(s,'コレクション',24,562);b=panel(s,20,594,353,320)
    for i,(t,ico,tg) in enumerate([('同期','sync','M36'),('読み込み・書き出し','file','M38'),('バックアップ','shield','M41'),('ノートタイプ','edit','M15'),('データベース・メディア確認','box','M43')]):row(b,t,i*64,ico=ico,target=tg)
    b=panel(s,20,942,353,128);row(b,'ヘルプ・URLスキーム',0,ico='info',target='M60');row(b,'言語 / このアプリについて',64,'日本語',target='M45')
    text(s,'Negoto  ·  自分のペースで、長く覚える',20,1100,353,11,C['muted'],align='center')
    form_screen('M31','デッキオプション',[
        ('プリセット',[('プリセット','標準','M32'),('プリセットを複製・適用','3デッキ','M33')]),
        ('1日の上限',[('新規カード','20'),('最大復習数','200'),('適用範囲','このデッキ','M33'),('今日だけ上限を変更','','M34')]),
        ('学習のしくみ',[('FSRS',True,'M32'),('目標保持率','90%','M32'),('学習ステップ','1m 10m','M33'),('詳細オプション','','M33')])],back='M02',footer=('変更を保存','M02'))
    s=screen('M32','FSRS',back='M31',tab=None,h=1090)
    b=panel(s,20,132,353,181);text(b,'覚える量と、復習の量を。',18,17,317,19,weight=600);text(b,'目標保持率',18,60,317,12,C['muted']);text(b,'90%',18,86,317,38,C['blue'],700);progress(b,18,151,317,.64)
    note(s,'保持率を上げるほど、復習回数が増えます。\n過去の学習履歴から間隔を最適化します。',20,333,353,74)
    b=panel(s,20,427,353,320)
    row(b,'FSRS を有効にする',0,on=True);row(b,'パラメータを最適化',64,'10/1 実行',target='M32');row(b,'精度を評価',128,'RMSE 4.8%',target='M32');row(b,'復習量のシミュレーション',192,target='M61');row(b,'変更時に再スケジュール',256,on=False)
    b=panel(s,20,768,353,128);row(b,'履歴を使い始める日',0,'すべて');row(b,'パラメータ / 詳細',64,'21個',target='M33')
    button(s,'設定を保存',20,945,353,'M31')
    form_screen('M33','詳細オプション',[
        ('表示順と延期',[('新規の収集 / 並び順','デッキ / ランダム'),('新規と復習の順番','復習を先に'),('復習の並び順','期日順'),('兄弟カードを延期',True)]),
        ('学習・再学習',[('学習 / 再学習ステップ','1m 10m / 10m'),('リーチ判定 / 動作','8回 / 保留'),('最大間隔','36,500日'),('SM-2：卒業 / 簡単な間隔','1日 / 4日')]),
        ('音声・時間・スケジュール',[('音声を自動再生',True),('タイマー / 自動送り','','M44'),('Easy Days','日曜日を軽く'),('カスタムスケジューリング','','M16'),('SM-2：易しさ・倍率','','M26')])],back='M31',footer=('詳細を保存','M31'))
    form_screen('M34','カスタム学習',[
        ('今日の上限',[('新規カードを増やす','+10枚'),('復習カードを増やす','+50枚')]),
        ('集中して復習',[('最近忘れたカード','過去7日','M35'),('先取り復習','7日先まで','M35'),('新規カードをプレビュー','過去3日','M35'),('状態・タグを選んで学習','','M35')])],back='M02',footer=('フィルタ条件を設定','M35'))
    s=screen('M35','フィルタデッキ',back='M34',tab=None,h=1070)
    label(s,'検索式',24,128);b=panel(s,20,159,353,83,stroke=C['blue']);text(b,'deck:English rated:7:1',18,24,317,14)
    b=panel(s,20,265,353,320);row(b,'デッキ名',0,'苦手な表現');row(b,'取得する枚数',64,'50 枚');row(b,'取得順',128,'忘却回数の多い順');row(b,'2つ目のフィルタ',192,on=False);row(b,'回答に応じて再スケジュール',256,on=True)
    note(s,'オン：次回の復習予定を更新します。\nオフ：元の予定を保って練習します。',20,607,353,78)
    text(s,'検索に一致：32枚  /  取得可能：28枚',24,717,345,14,weight=600)
    text(s,'保留・延期・別のフィルタ内のカードは除外',24,752,345,11,C['muted'])
    button(s,'28枚で構築する',20,801,353,'M04');button(s,'再構築',20,866,170,'M04',style='soft');button(s,'空にする',202,866,171,'M02',style='soft')
    text(s,'空にするとカードは元のデッキに戻ります',20,939,353,11,C['muted'],align='center')
    s=screen('M36','同期',back='M30',tab=None)
    b=panel(s,20,130,353,170);icon(b,'cloud',153,25,46,C['blue']);text(b,'すべて最新です',18,91,317,20,weight=600,align='center');text(b,'最終同期：今日 9:41',18,132,317,12,C['muted'],align='center')
    b=panel(s,20,323,353,256);row(b,'同期先',0,'AnkiWeb');row(b,'画像・音声を同期',64,on=True);row(b,'メディアの同期状況',128,'1,284 / 1,284');row(b,'一方向の同期',192,target='M37')
    note(s,'オフラインでも学習できます。\n接続が戻ったら変更を同期します。',20,601,353,72)
    button(s,'今すぐ同期',20,724,353,'M36',ico='sync')
    s=screen('M37','同期するデータを選択',back='M36',tab=None,h=950)
    note(s,'両方のコレクションに大きな変更があります。\nどちらを残すか選んでください。',20,126,353,84,color='amber')
    for y,title,time,detail,ico in [(236,'この端末','今日 9:41','3,200枚 · 128回の回答','person'),(438,'AnkiWeb','昨日 22:18','3,192枚 · 92回の回答','cloud')]:
        b=panel(s,20,y,353,177);icon(b,ico,18,20,24,C['blue']);text(b,title,57,17,269,18,weight=600);text(b,time,18,61,317,13,C['muted']);text(b,detail,18,94,317,14);text(b,'こちらを残す →',18,137,317,13,C['blue'],600);hit(b,0,0,353,177,'M62' if title=='この端末' else 'M70',title)
    text(s,'選んでいない側のノートと履歴を置き換えます。\n先に、この端末のバックアップを作成します。',24,648,345,13,C['muted'],h=65)
    button(s,'同期をキャンセル',20,756,353,'M36',style='soft')
    s=screen('M38','読み込む',back='M30',tab=None)
    b=panel(s,20,132,353,186);icon(b,'download',150,26,51,C['blue']);text(b,'使い慣れたデッキを、そのまま。',18,105,317,16,weight=600,align='center');text(b,'.apkg  .colpkg  .csv  .tsv',18,147,317,13,C['muted'],align='center')
    button(s,'ファイルを選択',20,342,353,'M39',ico='file')
    label(s,'読み込み方法',24,421);b=panel(s,20,455,353,192);row(b,'Anki デッキパッケージ',0,'統合','M63');row(b,'コレクション全体',64,'復元','M63');row(b,'テキスト / CSV',128,'フィールド対応','M39')
    button(s,'書き出しへ',20,703,353,'M40',style='soft')
    s=screen('M39','フィールドを対応付け',back='M38',tab=None,h=1010)
    badge(s,'vocabulary.csv · 240行',24,127,215)
    b=panel(s,20,179,353,320)
    for i,(t,v) in enumerate([('ノートタイプ','基本（表裏）'),('読み込み先','Everyday English'),('列1：word','Front'),('列2：meaning','Back'),('列3：category','タグ')]):row(b,t,i*64,v,target='M19' if i==0 else None)
    b=panel(s,20,519,353,192);row(b,'区切り文字 / 文字コード',0,'コンマ / UTF-8');row(b,'先頭行を見出しとして使う',64,on=True);row(b,'重複するノート',128,'更新する')
    note(s,'追加 224 · 更新 14 · スキップ 2\n読み込み前に差分を確認できます。',20,733,353,72)
    button(s,'238ノートを読み込む',20,855,353,'M64')
    form_screen('M40','書き出す',[
        ('対象と形式',[('対象','すべてのデッキ','M02'),('形式','Anki .apkg'),('コレクション全体','.colpkg'),('テキスト出力','.tsv')]),
        ('含めるデータ',[('学習の進み具合',True),('画像と音声',True),('デッキプリセット',True),('旧バージョンと互換',False)])],footer=('共有シートで保存','M30'))
    s=screen('M41','バックアップ',back='M30',tab=None,h=980)
    note(s,'ノート・設定・学習履歴を自動保存します。\n画像・音声は書き出しで別に保存できます。',20,128,353,76)
    b=panel(s,20,230,353,128);row(b,'自動バックアップ',0,on=True);row(b,'保持する世代数',64,'30')
    label(s,'復元ポイント',24,386);b=panel(s,20,422,353,256)
    for i,(t,v) in enumerate([('今日 9:32','3,200枚'),('昨日 22:18','3,192枚'),('10月4日 19:02','3,180枚'),('10月3日 8:14','3,160枚')]):row(b,t,i*64,v,target='M65')
    button(s,'今すぐバックアップ',20,709,353,'M41',style='soft');button(s,'外部ファイルから復元',20,779,353,'M38',style='soft')
    form_screen('M42','プロフィール',[
        ('プロフィールを切り替え',[('自分の学習','選択中','M30'),('資格の勉強','別のAnkiWeb','M30'),('プロフィールを追加','','M42')]),
        ('選択中のプロフィール',[('名前','自分の学習'),('AnkiWeb アカウント','接続済み','M36'),('ログアウト','','M36')])],footer=('切り替えて続ける','M01'))
    s=screen('M43','コレクションの確認',back='M30',tab=None)
    b=panel(s,20,130,353,193);icon(b,'shield',20,23,29,C['green']);text(b,'データベースは正常です',62,22,267,18,weight=600);text(b,'3,200枚のカードを確認しました',20,76,313,12,C['muted']);button(b,'もう一度確認',18,122,317,'M43',style='soft')
    label(s,'メディアの確認結果',24,355);b=panel(s,20,390,353,192);row(b,'見つからないファイル',0,'2 ファイル','M69');row(b,'使われていないファイル',64,'12 ファイル','M68');row(b,'空のカード',128,'3 枚','M10')
    button(s,'未使用メディアを確認',20,613,353,'M68',style='soft');text(s,'削除するファイルを確認してから実行します',24,690,345,12,C['muted'])
    form_screen('M44','操作と音声',[
        ('学習操作',[('タップ領域','9領域 × 表裏','M66'),('スワイプ','4方向','M66'),('上・下ツールバー','操作を並べ替え','M66'),('ゲームパッド・キーボード','','M66'),('シェイク / 連続タップ防止','取り消し / オン')]),
        ('音声と進行',[('音声を自動再生',True),('自動送り','オフ'),('表面 / 裏面の待ち時間','5秒 / 8秒'),('回答後の操作','普通 / 次へ'),('消音スイッチを無視',False),('TTS / 音声・再生速度','日本語 / 1.0×')]),
        ('時刻',[('1日の開始時刻','4:00'),('先取り学習','20分')])],footer=('設定を保存','M30'))
    form_screen('M45','表示とアクセシビリティ',[
        ('表示',[('テーマ','システム','M45'),('文字サイズ','標準 / Dynamic Type'),('コントラストを上げる',False),('動きを減らす',False),('インターフェース言語','日本語')]),
        ('学習画面',[('次回の間隔を表示',True),('カードの拡大率を維持',True),('入力式のキーボードを表示',True),('上下バーを表示',True),('Pencilのみで手書き',True)])],footer=('設定を保存','M30'))

def build_states():
    s=screen('M46','デッキを作成',back='M03',tab=None)
    label(s,'デッキ名',24,132);b=panel(s,20,167,353,65,stroke=C['blue']);text(b,'Everyday English',18,20,317,17)
    b=panel(s,20,267,353,128);row(b,'親デッキ',0,'なし');row(b,'プリセット',64,'標準','M31')
    note(s,'親デッキを選ぶと、サブデッキとして\nまとめて学習できます。',20,423,353,73)
    button(s,'作成する',20,723,353,'M01')
    s=screen('M47','共有デッキ',back='M03',tab=None)
    note(s,'AnkiWebの共有デッキを探して、\nダウンロードしたファイルを読み込みます。',20,132,353,76)
    b=panel(s,20,234,353,64);icon(b,'search',18,22,22);text(b,'言語・テーマで検索',53,21,272,15,C['muted'])
    b=panel(s,20,325,353,192);row(b,'語学',0,ico='deck',target='M38');row(b,'医学・科学',64,ico='deck',target='M38');row(b,'資格・試験',128,ico='deck',target='M38')
    button(s,'AnkiWebを開く',20,566,353,None,ico='cloud')['external']='https://ankiweb.net/shared/decks'
    s=screen('M48','削除を確認',back='M12',tab=None)
    icon(s,'trash',170,150,52,C['red']);text(s,'12ノートを削除しますか？',20,256,353,22,weight=650,align='center')
    note(s,'関連する24枚のカードも削除されます。\n対象ノートを確認してから削除してください。',20,324,353,78,color='red')
    b=panel(s,20,427,353,128);row(b,'対象ノート',0,'12');row(b,'関連するカード',64,'24')
    button(s,'12ノートを削除',20,623,353,'M10',style='danger');button(s,'キャンセル',20,686,353,'M12',style='soft')
    s=screen('M49','入力した答え',back='M06',tab=None)
    b=panel(s,20,158,353,340);text(b,'「継続は力なり」',20,35,313,25,weight=600,align='center');badge(b,'入力と一致しました',83,123,187,'green');text(b,'Practice makes perfect.',20,189,313,21,weight=600,align='center');icon(b,'audio',164,265,25,C['blue'])
    text(s,'答えを思い出す難しさで評価しましょう',20,548,353,12,C['muted'],align='center')
    for i,(t,c) in enumerate([('もう一度','red'),('難しい','amber'),('普通','green'),('簡単','blue')]):
        b=panel(s,20+i*91,724,80,54,C[c+'Soft'],12);text(b,t,2,17,76,13,C[c],600,align='center');hit(b,0,0,80,54,'M09',t)
    s=screen('M50','手書きパッド',back='M05',tab=None)
    text(s,'木漏れ日',20,146,353,34,weight=600,align='center');text(s,'文字を書いて、思い出す。',20,218,353,14,C['muted'],align='center')
    b=panel(s,20,283,353,340);rule(b,20,170,313);rect(b,176,20,1,300,C['line']);text(b,'木',90,96,175,113,C['ink'],300,align='center')
    b=panel(s,20,643,353,55);icon(b,'pencil',22,16,23,C['blue']);icon(b,'undo',99,16,23);icon(b,'trash',173,16,23);text(b,'Pencil',245,17,85,12,C['muted'])
    button(s,'答えを表示',20,731,353,'M05')
    form_screen('M51','延期と保留',[
        ('対象',[('カード','このカードのみ'),('ノート','兄弟カードを含む')]),
        ('操作',[('明日まで延期','','M10'),('延期を解除','','M10'),('保留する','','M10'),('保留を解除','','M10')])],back='M07',footer=('選択した操作を適用','M10'))
    s=screen('M52','音声を聞き比べる',back='M07',tab=None)
    for y,title,detail in [(138,'カードの音声','komorebi.mp3 · 0:08'),(377,'自分の録音','録音済み · 0:06')]:
        b=panel(s,20,y,353,214);text(b,title,18,15,317,17,weight=600);text(b,detail,18,51,317,12,C['muted'])
        for i in range(36):hh=8+((i*11+3)%35);rect(b,20+i*8.8,101-hh/2,3,hh,C['blue'],2)
        icon(b,'undo',62,164,22);icon(b,'play',165,160,29,C['blue']);icon(b,'more',269,164,22)
    button(s,'もう一度録音する',20,641,353,'M52',style='soft',ico='mic');button(s,'カードに戻る',20,710,353,'M05')
    form_screen('M53','リマインダー',[
        ('毎日の学習',[('通知を有効にする',True),('時刻','20:30'),('繰り返し','毎日'),('復習待ちの枚数を表示',True)]),
        ('通知プレビュー',[('今日の学習を少しだけ','残り72枚')])],footer=('保存する','M30'))
    s=screen('M54','はじめてのNegoto',tab='deck')
    icon(s,'deck',159,183,74,C['blue']);text(s,'覚えたいことから、はじめよう。',20,326,353,20,weight=650,align='center');text(s,'Ankiのデッキを読み込むことも、\n自分のカードをつくることもできます。',20,378,353,14,C['muted'],h=64,align='center')
    button(s,'デッキを読み込む',20,501,353,'M38',ico='download');button(s,'最初のカードをつくる',20,570,353,'M13',style='soft')
    s=screen('M55','同期を再開できます',back='M36',tab=None)
    icon(s,'cloud',163,173,65,C['amber']);text(s,'接続が途切れました',20,295,353,24,weight=650,align='center');text(s,'学習内容はこの端末に保存されています。\n通信が戻ってから、もう一度試せます。',20,354,353,14,C['muted'],h=72,align='center')
    b=panel(s,20,467,353,128);row(b,'未同期の変更',0,'8ノート / 24回答');row(b,'メディア',64,'残り2ファイル')
    button(s,'再試行',20,642,353,'M36');button(s,'オフラインで続ける',20,709,353,'M01',style='soft')
    form_screen('M56','ノートタイプを変更',[
        ('変更先',[('ノートタイプ','基本（表裏）','M15')]),
        ('フィールド対応',[('Front →','Front'),('Back →','Back'),('Example →','Extra')]),
        ('カード対応',[('カード1 →','カード1'),('カード2 →','新しく生成')])],back='M12',footer=('12ノートを変更','M10'))
    form_screen('M57','検索と置換',[
        ('置換する内容',[('検索','sun light'),('置換後','sunlight'),('対象フィールド','Back'),('大文字と小文字を区別',False),('正規表現',False)]),
        ('プレビュー',[('該当するノート','4 / 12'),('sun light → sunlight','4箇所')])],back='M12',footer=('4箇所を置換','M10'))
    s=screen('M58','カードプレビュー',back='M13',tab=None)
    chip(s,'表面',20,127,169,True,'M04');chip(s,'裏面',203,127,170,False,'M05')
    b=panel(s,20,188,353,389);text(b,'穴埋めと数式',20,26,313,15,C['muted'],align='center');text(b,'光合成では […] がつくられる。',20,101,313,19,weight=600,align='center');text(b,'E = mc²',20,189,313,42,weight=500,align='center');text(b,'MathJax · HTML · 画像 · 音声',20,306,313,12,C['muted'],align='center')
    button(s,'編集に戻る',20,715,353,'M13',style='soft')
    form_screen('M59','メディアを追加',[
        ('画像・ファイル',[('写真ライブラリ','','M14'),('カメラで撮影','','M14'),('ファイルから選ぶ','','M13'),('画像穴埋めをつくる','','M14')]),
        ('音声と手書き',[('音声を録音','','M52'),('手書きを画像として追加','','M50')])],back='M13')
    form_screen('M60','ヘルプと連携',[
        ('学習ガイド',[('基本の使い方','','M54'),('検索式のヘルプ','','M11'),('カードテンプレート','','M16')]),
        ('他のアプリから',[('デッキを開く','URLスキーム'),('追加画面を開く','フィールドを指定'),('ファイル共有','Files / Share Sheet')])],back='M30')
    s=screen('M61','復習量のシミュレーション',back='M32',tab=None,h=970)
    chartcard(s,20,132,353,310,'これから1年の学習量','約 24 分 / 日',[24,26,30,35,40,41,43,47,43,39,39,41],sub='目標保持率90% · 新規20枚 / 日')
    b=panel(s,20,467,353,256);row(b,'期間',0,'365日');row(b,'新規カード / 日',64,'20');row(b,'目標保持率',128,'90%');row(b,'Easy Days を反映',192,on=True)
    button(s,'再計算',20,773,353,'M61',style='soft')
    s=screen('M62','この端末の内容を送信',back='M37',tab=None)
    note(s,'AnkiWebのコレクションを、この端末の\nノート・設定・学習履歴で置き換えます。',20,140,353,80,color='amber')
    b=panel(s,20,253,353,192);row(b,'保存するコレクション',0,'この端末');row(b,'送信するカード',64,'3,200枚');row(b,'事前バックアップ',128,'作成済み')
    button(s,'AnkiWebを置き換える',20,587,353,'M36');button(s,'選び直す',20,654,353,'M37',style='soft')
    form_screen('M63','読み込み内容を確認',[
        ('everyday-english.apkg',[('新しく追加','224ノート'),('既存のノートを更新','14ノート'),('重複でスキップ','2ノート'),('メディア','486ファイル')]),
        ('読み込み設定',[('学習スケジュールを含める',True),('既存データと統合',True),('コレクションを置換',False)])],back='M38',footer=('読み込みを開始','M64'))
    s=screen('M64','読み込みが完了しました',back='M38',tab=None)
    add(s,'ellipse',147,160,100,100,'Success',fill=C['greenSoft']);icon(s,'check',180,193,36,C['green']);text(s,'238ノートを読み込みました',20,305,353,21,weight=650,align='center')
    b=panel(s,20,375,353,192);row(b,'追加',0,'224ノート');row(b,'更新',64,'14ノート');row(b,'スキップ',128,'2ノート')
    button(s,'デッキを見る',20,626,353,'M01');button(s,'読み込みログ',20,691,353,'M63',style='soft')
    s=screen('M65','バックアップから復元',back='M41',tab=None)
    badge(s,'10月5日 22:18',24,136,145);text(s,'3,192枚のカード',24,187,345,27,weight=650)
    note(s,'現在のコレクションを置き換えます。\n復元前の状態もバックアップに残します。',20,268,353,78,color='amber')
    b=panel(s,20,375,353,128);row(b,'復元するノート・履歴',0,'10月5日時点');row(b,'メディア',64,'この端末のものを使用')
    button(s,'このバックアップを復元',20,626,353,'M36');button(s,'キャンセル',20,691,353,'M41',style='soft')
    s=screen('M66','操作をカスタマイズ',back='M44',tab=None,h=1030)
    chip(s,'タップ',20,130,110,True);chip(s,'スワイプ',142,130,110);chip(s,'ボタン',264,130,109)
    label(s,'答えを表示しているとき',24,192)
    for r in range(3):
        for col in range(3):
            xx=20+col*121;yy=225+r*88;b=panel(s,xx,yy,111,78,C['redSoft'] if col==0 else C['greenSoft'] if col==2 else C['surface'],13);text(b,['もう一度','何もしない','普通'][col],4,29,103,12,C['red'] if col==0 else C['green'] if col==2 else C['muted'],500,align='center')
    label(s,'キーボード / ゲームパッド',24,518);b=panel(s,20,552,353,256)
    row(b,'Space / A ボタン',0,'答えを表示');row(b,'1・2・3・4',64,'回答評価');row(b,'Z / B ボタン',128,'取り消し');row(b,'ユーザー操作 1〜8',192,'JSアクション')
    button(s,'割り当てを保存',20,864,353,'M44')
    s=screen('M67','デッキを削除',back='M03',tab=None)
    icon(s,'deck',168,147,57,C['red']);text(s,'Everyday English を削除',20,261,353,22,weight=650,align='center')
    note(s,'このデッキとサブデッキ、含まれるカードを\n削除します。ほかのデッキは残ります。',20,332,353,79,color='red')
    b=panel(s,20,438,353,128);row(b,'削除するデッキ',0,'1 + サブデッキ2');row(b,'含まれるカード',64,'1,240枚')
    button(s,'デッキを削除する',20,630,353,'M01',style='danger');button(s,'キャンセル',20,695,353,'M03',style='soft')
    s=screen('M68','未使用メディア',back='M43',tab=None)
    badge(s,'12ファイル · 8.4 MB',24,133,204,'amber');b=panel(s,20,189,353,256)
    for i,t in enumerate(['old-audio.mp3','draft-image.png','lesson-02.m4a','ほか9ファイル']):row(b,t,i*64,'未使用')
    note(s,'どのノートからも使われていないファイルです。\n削除対象を確認してから実行してください。',20,476,353,78,color='amber')
    button(s,'12ファイルを削除',20,630,353,'M43',style='danger');button(s,'キャンセル',20,695,353,'M43',style='soft')
    s=screen('M69','見つからないメディア',back='M43',tab=None)
    note(s,'参照されている2ファイルが見つかりません。\n同期か元のデッキから復元できます。',20,134,353,78,color='amber')
    b=panel(s,20,243,353,128);row(b,'komorebi-02.mp3',0,'音声','M10');row(b,'plant-diagram.png',64,'画像','M10')
    button(s,'メディア同期を再試行',20,421,353,'M36',style='soft');button(s,'元のデッキを読み込む',20,487,353,'M38',style='soft')
    s=screen('M70','AnkiWebの内容を受信',back='M37',tab=None)
    note(s,'この端末のコレクションを、AnkiWebの\nノート・設定・学習履歴で置き換えます。',20,140,353,80,color='amber')
    b=panel(s,20,253,353,192);row(b,'保存するコレクション',0,'AnkiWeb');row(b,'受信するカード',64,'3,192枚');row(b,'事前バックアップ',128,'作成済み')
    button(s,'この端末を置き換える',20,587,353,'M36');button(s,'選び直す',20,654,353,'M37',style='soft')

def ipad(key,title,active='deck',w=1194,h=834,sub=''):
    s=dict(key=key,title=title,name=key+' · iPad / '+title,page=PRODUCT_PAGE,w=w,h=h,fill=C['bg'],children=[],theme='dark' if C is DARK else 'light')
    SCREENS.append(s)
    text(s,'9:41   10月6日 火曜日',25,9,230,11,weight=500)
    text(s,'100%',w-77,9,52,11,C['muted'],align='right')
    b=panel(s,12,40,230,h-58,C['surface'],20,'Navigation / Regular sidebar')
    icon(b,'deck',21,26,29,C['blue']);text(b,'Negoto',63,21,146,24,weight=700)
    text(b,'自分のペースで、長く覚える',21,69,195,10,C['muted'])
    for i,(ico,t,tg) in enumerate([('deck','今日の学習','I01'),('search','ブラウズ','I03'),('chart','統計','I04'),('settings','設定','I08')]):
        yy=112+i*54
        if ico==active:rect(b,12,yy,206,44,C['blueSoft'],12)
        icon(b,ico,26,yy+11,22,C['blue'] if ico==active else C['muted']);text(b,t,63,yy+10,137,14,C['blue'] if ico==active else C['ink'],600 if ico==active else 400);hit(b,12,yy,206,44,tg,t)
    rule(b,21,351,188);label(b,'マイデッキ',22,376,185)
    for i,t in enumerate(['Everyday English','日本語 / 表現','医学 / 基礎']):icon(b,'deck',23,416+i*45,18);text(b,t,52,412+i*45,159,12);hit(b,15,402+i*45,200,44,'I10',t)
    label(b,'保存した検索',22,568,185);text(b,'#  苦手なカード',23,609,189,12,C['muted']);text(b,'#  最近追加したカード',23,646,189,12,C['muted'])
    icon(b,'sync',23,h-118,19,C['green']);text(b,'すべて同期済み',55,h-123,145,11,C['muted']);hit(b,12,h-135,207,46,'I09','同期')
    text(s,title,272,60,w-472,28,weight=700)
    if sub:text(s,sub,273,107,w-350,12,C['muted'])
    ib(s,'plus',w-74,59,'I06')
    rect(s,w/2-72,h-10,144,4,C['ink'],2,'Home indicator')
    return s

def build_ipad():
    s=ipad('I01','今日の学習',sub='10月6日 火曜日 · 小さな積み重ねを、毎日に。')
    b=panel(s,271,151,567,269,C['navy'],22,'Today / iPad focus')
    text(b,'少しずつ、確かな記憶に。',24,21,519,19,'#D5E2FA',500)
    text(b,'72',24,65,171,76,'#FFFFFF',700);text(b,'枚 残っています',161,109,353,17,'#D5E2FA')
    text(b,'新規 20    学習中 8    復習 44',25,178,510,14,'#D5E2FA')
    button(b,'学習をはじめる',329,187,213,'I02',ico='play',h=56)
    b=panel(s,859,151,305,269,name='Today / Weekly activity')
    text(b,'今週のリズム',20,20,265,17,weight=600);text(b,'24日',20,63,140,37,weight=700);text(b,'連続して学習中',136,83,150,12,C['muted']);bars(b,20,137,265,75,[72,95,112,80,123,92,128],labels=['水','木','金','土','日','月','火'])
    section(s,'マイデッキ',273,451,380);decklist(s,271,494,567)
    b=panel(s,859,441,305,287);text(b,'今日の進み具合',20,20,265,17,weight=600);text(b,'128 / 200',20,71,265,34,weight=700);text(b,'64% 完了 · あと約12分',20,131,265,12,C['muted']);progress(b,20,176,265,.64);button(b,'統計を見る',20,212,265,'I04',style='soft')
    text(s,'学習を続けるだけで、次の復習は自動で調整されます。',275,770,875,12,C['muted'])
    s=ipad('I02','Everyday English',sub='学習中 · 3 / 40')
    b=panel(s,271,154,570,529,name='Study / iPad card')
    badge(b,'表現',242,31,86,'purple');text(b,'こもれび',24,89,522,15,C['muted'],align='center');text(b,'木漏れ日',24,127,522,50,weight=650,align='center');rule(b,46,243,478);text(b,'sunlight filtering through trees',33,280,504,26,weight=600,align='center');text(b,'The forest floor glowed with\nsunlight filtering through the leaves.',36,346,498,17,C['muted'],h=80,align='center');ib(b,'audio',263,451,'M52')
    b=panel(s,862,154,302,529,name='Inspector / Card information')
    text(b,'カード情報',20,21,262,18,weight=650)
    for i,(t,v) in enumerate([('次の復習','12日後'),('復習回数','18回'),('安定度','18.2日'),('難易度','4.8'),('想起確率','92.6%')]):row(b,t,65+i*58,v,h=58)
    chip(b,'日常表現',18,390,102,True);chip(b,'自然',132,390,66,True);button(b,'ノートを編集',18,451,266,'I06',style='soft')
    for i,(t,iv,c) in enumerate([('もう一度','1分','red'),('難しい','6日','amber'),('普通','12日','green'),('簡単','24日','blue')]):
        xx=272+i*146;text(s,iv,xx,702,133,11,C['muted'],align='center');b=panel(s,xx,731,132,56,C[c+'Soft'],14);text(b,t,8,17,116,15,C[c],600,align='center');hit(b,0,0,132,56,'I01',t)
    ib(s,'undo',960,737,'I02');ib(s,'more',1022,737,'M07');ib(s,'close',1084,737,'I01')
    s=ipad('I03','ブラウズ','search',w=1366,h=1024,sub='3,200枚のカード · 検索と編集を、ひとつの画面で。')
    b=panel(s,271,145,594,52);icon(b,'search',18,16,22);text(b,'deck:English is:due',58,16,500,14)
    ib(s,'filter',879,149,'M11');chip(s,'選択',270,220,91,target='M12');chip(s,'タグ',375,220,80,target='M18');text(s,'24件 · 期日の早い順',604,225,290,12,C['muted'],align='right')
    b=panel(s,271,279,652,657,name='Browser / Table')
    text(b,'表面',20,15,338,12,C['muted'],600);text(b,'期日',421,15,90,12,C['muted'],600);text(b,'間隔',535,15,92,12,C['muted'],600)
    for i,(word,meaning) in enumerate([('木漏れ日','sunlight filtering through trees'),('一期一会','once-in-a-lifetime encounter'),('懐かしい','nostalgic'),('いただきます','gratitude before a meal'),('おつかれさま','thank you for your hard work'),('余韻','lingering resonance'),('思いやり','consideration for others')]):
        yy=54+i*82
        if i==0:rect(b,9,yy,634,78,C['blueSoft'],12)
        text(b,word,22,yy+12,382,16,weight=600);text(b,meaning,22,yy+41,385,11,C['muted']);text(b,'今日' if i<3 else '10/8',421,yy+26,90,13,C['green']);text(b,'12日',535,yy+26,86,13,C['muted']);hit(b,10,yy,632,78,'I06',word)
    text(s,'24枚中 7枚を表示 · ⌘F 検索  /  ⌘↵ 保存',273,958,650,12,C['muted'])
    editor(s,943,145,393,652);button(s,'変更を保存',943,820,393,'I03');button(s,'テンプレート',943,885,393,'I07',style='soft')
    s=ipad('I04','統計','chart',sub='すべてのデッキ · 過去1か月')
    chip(s,'概要',271,143,99,True,'I04');chip(s,'履歴',382,143,99,False,'I12');chip(s,'記憶',493,143,99,False,'I05');chip(s,'保持率',604,143,99,False,'M23');chip(s,'全デッキ',914,143,109,True,'I10');chip(s,'1か月',1035,143,128,True)
    for i,(v,l,c) in enumerate([('128','今日の回答数','blue'),('18分24秒','今日の学習時間','ink'),('91.8%','1か月の保持率','green'),('24日','連続学習日数','ink')]):
        b=panel(s,271+i*228,200,209,120);text(b,l,17,14,175,12,C['muted']);text(b,v,17,49,175,30,C[c],700)
    b=panel(s,271,340,567,212,name='Statistics / Calendar regular');text(b,'学習カレンダー',19,15,525,15,weight=600);text(b,'7月                       8月                       9月                       10月',19,50,524,11,C['muted']);heatmap(b,19,80,529,7,29)
    b=panel(s,859,340,305,212);text(b,'コレクション',18,15,269,15,weight=600);text(b,'3,200',18,51,269,37,weight=700)
    for i,(lab,v,c) in enumerate([('成熟','1,660','green'),('未成熟','780','blue'),('未学習','620','purple'),('保留ほか','140','amber')]):
        xx=18+(i%2)*141;yy=118+(i//2)*39;rect(b,xx,yy+7,7,7,C[c],2);text(b,lab,xx+14,yy,65,10,C['muted']);text(b,v,xx+71,yy,55,11,weight=600,align='right')
    chartcard(s,271,573,435,217,'これからの復習','304 枚',[44,38,56,32,47,35,52],sub='今後7日間 · 1日平均43.4枚',color=C['green'])
    chartcard(s,725,573,439,217,'学習時間','8時間42分',[12,18,21,14,23,20,16,18,24,19,17,21],sub='過去1か月 · 平均17.4分 / 日')
    s=ipad('I05','記憶の状態','chart',sub='FSRS · すべてのデッキ · 過去1か月')
    chip(s,'概要',271,143,99,False,'I04');chip(s,'履歴',382,143,99,False,'I12');chip(s,'記憶',493,143,99,True,'I05');chip(s,'保持率',604,143,99,False,'M23')
    for x,y,title,v,values,sub in [(271,200,'復習間隔','中央値24日',[10,36,95,142,121,68,34,12],'日 / カード数'),(725,200,'安定度','平均32.4日',[9,28,64,120,148,106,57,32],'想起確率が90%になるまでの日数'),(271,493,'難易度','平均4.8',[8,26,78,123,144,108,71,43,12,6],'難易度1〜10 / カード数'),(725,493,'想起確率','92.6%',[2,3,5,8,13,18,35,64,136,194],'想起確率0〜100% / カード数')]:chartcard(s,x,y,439,272,title,v,values,sub)
    s=ipad('I06','ノートを編集','search',sub='基本（表裏） · Everyday English')
    editor(s,271,148,435,577);b=panel(s,727,148,437,577,name='Editor / Live preview')
    text(b,'カードプレビュー',23,22,391,17,weight=600);chip(b,'表面',24,69,187,True);chip(b,'裏面',223,69,190)
    text(b,'木漏れ日',25,180,387,39,weight=650,align='center');rule(b,34,280,369);text(b,'sunlight filtering through trees',29,319,379,22,weight=600,align='center');text(b,'The forest floor glowed with\nsunlight filtering through the leaves.',29,383,379,15,C['muted'],h=76,align='center');ib(b,'audio',195,491,'M52')
    button(s,'添付 / 穴埋め / 数式',271,745,280,'M59',style='soft');button(s,'変更を保存',882,745,282,'I03')
    s=ipad('I07','カードテンプレート','search',sub='基本（表裏） · カード1')
    chip(s,'表面',271,147,130,True);chip(s,'裏面',415,147,130);chip(s,'CSS',559,147,130)
    b=panel(s,271,207,567,508,C['navy'],18,'Template / Editor')
    text(b,'01   <div class="word">\n02     {{Front}}\n03   </div>\n04\n05   {{#Audio}}\n06     {{Audio}}\n07   {{/Audio}}\n08\n09   {{hint:Example}}\n10   {{tts ja_JP:Front}}',22,25,523,18,'#DDE7FF',h=438)
    b=panel(s,859,147,305,568);text(b,'プレビュー',18,18,269,17,weight=600);text(b,'木漏れ日',18,219,269,34,weight=600,align='center');text(b,'例文を見る',18,314,269,13,C['blue'],align='center')
    button(s,'フィールドを挿入',271,742,243,'M19',style='soft');button(s,'保存',921,742,243,'I06')
    s=ipad('I08','設定','settings',sub='学習環境を、自分に合わせる。')
    b=panel(s,271,150,307,580,name='Settings / Categories')
    for i,(t,tg) in enumerate([('学習とFSRS','M31'),('操作と音声','M44'),('表示とアクセシビリティ','M45'),('同期','I09'),('バックアップ','M41'),('ノートタイプ','M15'),('データの確認','M43'),('プロフィール','M42')]):row(b,t,i*70,target=tg,h=70)
    b=panel(s,599,150,565,580,name='Settings / Detail')
    text(b,'学習とFSRS',22,22,521,22,weight=650);text(b,'標準プリセット · 3デッキで使用中',22,69,521,13,C['muted'])
    for i,(t,v) in enumerate([('新規カード / 日','20'),('最大復習数 / 日','200'),('目標保持率','90%'),('学習ステップ','1m 10m')]):row(b,t,113+i*65,v,h=65)
    row(b,'FSRS を有効にする',373,on=True);button(b,'詳細オプション',20,453,525,'M33',style='soft')
    s=ipad('I09','同期','settings',sub='学習の続きは、どの端末でも。')
    b=panel(s,271,152,435,555);icon(b,'cloud',173,41,86,C['blue']);text(b,'すべて最新です',22,182,391,28,weight=650,align='center');text(b,'最終同期 今日9:41',22,236,391,14,C['muted'],align='center');button(b,'今すぐ同期',24,331,387,'I09',ico='sync');button(b,'同期履歴を確認',24,402,387,'M36',style='soft')
    b=panel(s,727,152,437,555)
    for i,(t,v,tg) in enumerate([('同期先','AnkiWeb',None),('画像・音声を同期',True,None),('メディア','1,284 / 1,284',None),('一方向の同期','','M37'),('バックアップ','','M41'),('プロフィール','','M42')]):row(b,t,i*78,'' if isinstance(v,bool) else v,target=tg,on=v if isinstance(v,bool) else None,h=78)
    s=ipad('I10','Everyday English',sub='毎日の英語を、自分の言葉に。')
    b=panel(s,271,154,567,221);text(b,'40',23,20,519,56,weight=700);text(b,'枚を、今日の記憶に。',130,57,414,19,C['muted']);text(b,'新規 12 · 学習中 4 · 復習 24',24,125,519,14,C['muted']);button(b,'学習をはじめる',291,147,252,'I02',ico='play')
    chartcard(s,271,396,567,325,'これからの復習','165 枚',[24,18,31,22,38,12,20],sub='今後7日間',color=C['green'])
    b=panel(s,859,154,305,567)
    for i,(t,v,tg) in enumerate([('カード総数','1,240',None),('目標保持率','90%','M32'),('カスタム学習','','M34'),('フィルタデッキ','','M35'),('デッキオプション','','M31'),('統計','','I04'),('読み込み・書き出し','','M38')]):row(b,t,i*76,v,target=tg,h=76)
    s=ipad('I11','画像穴埋め','search',sub='医学 / 基礎 · 3つのマスク')
    source=next(z for z in SCREENS if z['key']=='M14')
    diag=copy.deepcopy(next(n for n in source['children'] if n['name']=='Image occlusion / Editable masks'));diag.update(x=271,y=151,w=567,h=570)
    for n in diag['children']:n['x']+=107;n['y']+=70
    s['children'].append(diag)
    b=panel(s,859,151,305,570);text(b,'マスクを編集',18,20,269,19,weight=650)
    row(b,'隠し方',72,'すべて隠す');row(b,'マスク1',146,'葉');row(b,'マスク2',220,'茎');row(b,'マスク3',294,'根');button(b,'カードを作成',18,442,269,'I03')
    s=ipad('I12','学習の履歴','chart',sub='全デッキ · 過去1か月 · 3,842回の回答')
    chartcard(s,271,154,435,315,'復習回数','3,842 回',[88,103,82,143,131,96,151,170,123,129,132,128],sub='学習・再学習・未成熟・成熟・フィルタ')
    chartcard(s,727,154,437,315,'学習時間','8時間42分',[12,17,13,24,19,16,26,28,18,20,21,18],sub='1日平均17.4分 / 1回8.2秒')
    b=panel(s,271,490,435,246);text(b,'回答ボタン',20,18,395,16,weight=600)
    for i,(t,v,c) in enumerate([('もう一度','8%','red'),('難しい','12%','amber'),('普通','67%','green'),('簡単','13%','blue')]):
        xx=20+i*103;rect(b,xx,70,90,84,C[c+'Soft'],14);text(b,v,xx+3,91,84,25,C[c],700,align='center');text(b,t,xx,171,90,12,C['muted'],align='center')
    b=panel(s,727,490,437,246);text(b,'深く振り返る',20,19,397,16,weight=600);row(b,'実際の保持率',66,'91.8%','M23');row(b,'時間帯別',130,'朝6〜9時','M24')

def clone_theme(source,key,title):
    src=next(s for s in SCREENS if s['key']==source)
    s=copy.deepcopy(src);s.update(key=key,title=title,name=key+' · '+title,theme='dark')
    mapping={LIGHT[k]:DARK[k] for k in LIGHT}
    def recolor(n,parent_fill=None):
        old_fill=n.get('fill')
        for k in ['fill','color','stroke']:
            if k=='color' and n.get(k)=='#FFFFFF':n[k]=DARK['ink'] if parent_fill!=LIGHT['blue'] else DARK['bg']
            elif n.get(k) in mapping:n[k]=mapping[n[k]]
        if n.get('target') in {'M01','M04','M05','M20'}:n['target']={'M01':'D01','M04':'D02','M05':'D02','M20':'D03'}[n['target']]
        for c in n.get('children',[]):recolor(c,old_fill or parent_fill)
    recolor(s);SCREENS.append(s)

def build_adaptive():
    for key,w,h,title in [('R01',320,812,'iPhone / 最小幅320pt'),('R02',507,1024,'iPad / Split View 507pt')]:
        s=screen(key,'今日の学習',w=w,h=h,sub='10月6日 火曜日',action=('plus','M03'));s['name']=key+' · '+title
        b=panel(s,16,148,w-32,225,C['navy'],20);text(b,'少しずつ、確かな記憶に。',18,18,w-68,13,'#CFDCF5');text(b,'72',18,61,118,57,'#FFFFFF',700);text(b,'枚 残っています',118,91,w-164,12,'#CFDCF5');text(b,'新規20 · 学習中8 · 復習44',18,135,w-68,12,'#CFDCF5');button(b,'学習をはじめる',18,172,w-68,'M04',h=44)
        text(s,'今日の進み具合  128 / 200枚',18,394,w-36,12,C['muted']);progress(s,18,424,w-36,.64);section(s,'マイデッキ',18,448,w-36);b=decklist(s,16,484 if w==320 else 490,w-32)
        if w==320:
            for n in b['children']:
                if n.get('type')=='text' and '/' in n.get('text',''):n['text']=n['text'].split('/')[0].strip();n['w']=180
        if w>393:
            b=panel(s,16,748,w-32,139);text(b,'24日、続いています',18,16,w-68,18,weight=600);text(b,'毎日の小さな積み重ねが、長い記憶に。',18,59,w-68,13,C['muted']);button(b,'統計を開く',w-171,80,137,'M20',style='soft',h=44)
    s=ipad('R03','今日の学習',w=834,h=1194,sub='iPad 縦向き · 834pt')
    b=panel(s,271,148,533,257,C['navy'],22);text(b,'少しずつ、確かな記憶に。',24,24,485,18,'#CFDCF5');text(b,'72',24,75,170,65,'#FFFFFF',700);text(b,'枚 残っています',149,118,360,16,'#CFDCF5');button(b,'学習をはじめる',24,183,485,'I02',ico='play')
    section(s,'マイデッキ',273,438,490);decklist(s,271,482,533)
    b=panel(s,271,738,533,287);text(b,'今週のリズム',22,21,489,19,weight=600);text(b,'24日連続で学習しています',22,63,489,13,C['muted']);bars(b,22,120,489,101,[72,95,112,80,123,92,128],labels=['水','木','金','土','日','月','火'])
    button(s,'統計を見る',271,1060,533,'I04',style='soft')
    s=dict(key='R04',title='iPhone 横向き',name='R04 · iPhone landscape / 852 × 393',page=PRODUCT_PAGE,w=852,h=393,fill=C['bg'],children=[],theme='light');SCREENS.append(s)
    text(s,'9:41',22,8,70,12,weight=600);ib(s,'close',12,29,'M02');text(s,'Everyday English',79,40,360,18,weight=600);text(s,'12     4     24',616,43,187,13,C['muted'],align='right')
    b=panel(s,18,87,816,201);text(b,'こもれび',20,22,336,12,C['muted'],align='center');text(b,'木漏れ日',20,64,336,36,weight=600,align='center');rect(b,385,20,1,161,C['line']);text(b,'sunlight filtering\nthrough trees',412,36,379,23,weight=600,h=85,align='center');text(b,'The forest floor glowed with light.',412,143,379,13,C['muted'],align='center')
    for i,(t,c) in enumerate([('もう一度','red'),('難しい','amber'),('普通','green'),('簡単','blue')]):
        b=panel(s,18+i*209,307,189,48,C[c+'Soft'],12);text(b,t,4,13,181,14,C[c],600,align='center');hit(b,0,0,189,48,'M09',t)
    rect(s,364,379,124,4,C['ink'],2)
    clone_theme('M01','D01','Dark / 今日の学習');clone_theme('M05','D02','Dark / 学習');clone_theme('I04','D03','Dark / iPad統計')

def foundation(key,title,w=1440,h=980):
    s=dict(key=key,title=title,name=key+' · '+title,page='00 Foundations · 設計ガイド',w=w,h=h,fill=C['bg'],children=[],theme='light');SCREENS.append(s);return s

def build_foundations():
    s=foundation('F01','Negoto · Design direction',1440,1040)
    b=panel(s,0,0,1440,400,C['navy'],0,'Cover / Brand')
    text(b,'NEGOTO  /  iOS + iPadOS',54,42,1320,16,'#BFD0F3',600)
    text(b,'記憶は、毎日の中に。',50,111,1332,64,'#FFFFFF',700)
    text(b,'AnkiMobileの機能を、ひとつながりの学習体験へ。',55,226,1320,25,'#CDDCF7',400)
    text(b,'iPhone · iPad · Split View · Stage Manager · Light / Dark',55,320,1320,17,'#BFD0F3')
    for i,(n,title,desc) in enumerate([('01','学ぶ','学習の開始から回答、取り消し、手書き、音声まで。'),('02','整える','検索・一括操作・フィールド・テンプレート・画像穴埋め。'),('03','振り返る','学習量・カレンダー・保持率・FSRS・これからの復習。')]):
        b=panel(s,50+i*457,440,426,248);text(b,n,22,18,380,14,C['blue'],600);text(b,title,22,56,380,35,weight=650);text(b,desc,22,126,380,17,C['muted'],h=93)
    section(s,'デザインの読み方',54,729,1290)
    text(s,'01 Product の M はiPhone、I はiPad、R は幅・向きの検証、D はダーク表示です。\n画面内のボタンから主要な遷移を確認できます。数値・アカウント・グラフは説明用データです。',54,780,1310,20,C['muted'],h=92)
    note(s,'設計範囲：公式AnkiMobileの公開マニュアルと、参照されているAnki本体の標準機能。\nデザイン成果物です。現在のSwift実装に機能が追加されたことを意味しません。',50,901,1337,88)
    s=foundation('F02','Design system · Components',1440,1140)
    text(s,'迷わず使える、小さなルール。',44,33,1345,39,weight=700);text(s,'8ptを基準に、十分な余白と44pt以上の操作領域。日本語・英語の混在でも読みやすく。',47,101,1334,17,C['muted'])
    for i,(k,t) in enumerate([('blue','操作 / 新規'),('red','再学習 / 失敗'),('green','復習 / 成功'),('amber','注意 / 難しい'),('purple','ノート / タグ'),('ink','本文')]):
        x=47+i*228;rect(s,x,164,202,77,C[k],15);text(s,t,x,256,207,14,weight=600);text(s,C[k],x,285,207,12,C['muted'])
    b=panel(s,44,344,647,338);text(b,'文字の階層',23,18,601,16,C['muted'],600);text(b,'大切なものを、大きく。',23,62,601,34,weight=700);text(b,'学習をはじめる',23,127,601,24,weight=650);text(b,'本文は17ptを基準。補助情報は13pt以上。',23,186,601,17);text(b,'デザイン図の密度が高い箇所は縮小表現。実装ではDynamic Typeと改行で拡張。',23,241,599,14,C['muted'],h=70)
    b=panel(s,714,344,679,338);text(b,'ボタン / 状態',23,18,630,16,C['muted'],600);button(b,'学習をはじめる',23,73,300,None,ico='play');button(b,'プレビュー',346,73,310,None,style='soft');button(b,'削除を確認',23,143,300,None,style='danger');ib(b,'plus',349,143);ib(b,'sync',414,143);ib(b,'more',479,143);toggle(b,24,232,True);toggle(b,97,232,False);badge(b,'同期済み',180,232,109,'green');badge(b,'オフライン',310,232,119,'amber')
    b=panel(s,44,710,647,345);text(b,'カード・リスト・入力',23,18,601,16,C['muted'],600);row(b,'目標保持率',59,'90%');row(b,'音声を自動再生',126,on=True);chip(b,'全デッキ',22,215,144,True);chip(b,'過去1か月',181,215,144);progress(b,22,293,600,.64)
    b=panel(s,714,710,679,345,C['navy'],18);text(b,'Light と Dark',23,22,630,25,'#FFFFFF',650);text(b,'色は役割で管理します。\n数値や状態は色だけに頼らず、ラベルも併記します。\nUIの文字・背景・フォーカスはコントラストを確保。\nReduce Motion / VoiceOver / Keyboardを設計に含めます。',23,89,630,18,'#D0DEF7',h=211)
    s=foundation('F03','Responsive · Interaction specification',1440,1100)
    text(s,'端末名ではなく、使える幅で変わる。',43,39,1352,39,weight=700)
    cols=[(44,306,'Compact','320–599pt','タブバー + 1列\n一覧 → 詳細の順に表示\n設定・編集はフルスクリーン\n回答は4列、文字拡大時は2×2'),(373,307,'Regular','600–999pt','サイドバー + 詳細\n統計は利用可能幅で1〜2列\n編集のプレビューは切り替え\n狭いiPadはCompactへ'),(703,307,'Expanded','1,000pt〜','サイドバー + 2列コンテンツ\n学習情報をインスペクタへ\n編集とプレビューを並べる\n統計は2列、KPIは4列'),(1033,363,'Wide','1,300pt〜','ブラウズは3ペイン\nナビ + 一覧 + 編集\nウィンドウ幅が狭くなると\nインスペクタをシートに移動')]
    for x,w,t,v,desc in cols:
        b=panel(s,x,137,w,373);text(b,t,20,19,w-40,24,weight=650);badge(b,v,20,69,w-40);text(b,desc,20,125,w-40,17,C['muted'],h=226)
    b=panel(s,44,540,652,473);text(b,'レイアウト・スクロール',22,20,608,23,weight=650);text(b,'• 実装ではhorizontalSizeClassを優先、幅は参考値。\n• コンテンツ余白：Compact 20pt / Regular 28pt。\n• 統計カード：最小幅280pt、余裕がなければ1列。\n• 学習カード本文はスクロール。回答操作は下端に固定。\n• 長い統計・フォームは画面全体の縦スクロール。\n• キーボード表示時は保存・書式バーを可視領域へ。\n• Safe Area、回転、Split View、Stage Managerで再配置。\n• Dynamic Type最大時は説明と値を縦積みに。',22,85,608,17,C['muted'],h=343)
    b=panel(s,718,540,678,473);text(b,'操作とアクセシビリティ',22,20,634,23,weight=650);text(b,'• すべての主操作に44×44pt以上のタップ領域。\n• 選択・状態は色 + ラベル + アイコンで表現。\n• グラフには数値表・読み上げ順・単位を用意。\n• ⌘F 検索、⌘N 追加、Space 答え、1–4 評価。\n• フォーカス移動、Escape閉じる、Undoを保持。\n• ドラッグやスワイプにはメニューの代替操作。\n• 破壊的操作は対象件数・範囲・戻る手段を明示。\n• 読み込み中・空・失敗・オフラインを独立状態に。',22,85,634,17,C['muted'],h=343)
    s=foundation('F04','Feature coverage · 公式Ankiとの対応',1440,1170)
    text(s,'必要な操作に、必ずたどり着ける。',44,36,1352,38,weight=700);text(s,'基準：AnkiMobile公式マニュアル / Anki Manual · 2026-10-06確認',46,108,1346,16,C['muted'])
    items=[('デッキ・日々の学習','M01–09 / I01–02 / I10','階層、追加、移動、4段階評価、入力式、取り消し、完了'),('学習ツール','M07–08 / M49–52 / M66','フラグ、マーク、カード/ノート延期・保留、音声、録音、手書き'),('ブラウズ・編集','M10–19 / M56–59 / I03 / I06–07','全検索式、一括操作、タグ、ノートタイプ、テンプレート、画像穴埋め'),('統計','M20–26 / I04–05 / I12','今日、履歴、時間、予測、カレンダー、保持率、間隔、Ease、FSRS'),('スケジューリング','M31–35 / M61 / I08','プリセット、SM-2、FSRS最適化、学習/再学習、上限、順序、Easy Days'),('データ・アカウント','M36–43 / M62–65 / I09','AnkiWeb、競合、インポート、CSV対応付け、エクスポート、復元、プロフィール'),('設定・連携・状態','M44–48 / M53–55 / M60 / M66','TTS、入力割当、通知、表示、URLスキーム、空、エラー、削除確認')]
    for i,(title,ids,desc) in enumerate(items):
        y=161+i*125;b=panel(s,44,y,1352,108);text(b,title,20,14,330,19,weight=650);text(b,ids,395,15,920,14,C['blue'],600);text(b,desc,395,53,920,15,C['muted'])
    text(s,'PC版のアドオン実行・外部LaTeXコンパイルはAnkiMobileと同じ範囲外。描画互換はテンプレートとメディアで扱います。',46,1076,1348,14,C['muted'])

def escaped(s): return html.escape(str(s),quote=True)

def svg_node(n):
    x,y,w,h=n['x'],n['y'],n['w'],n['h'];kind=n['type']
    title='<title>'+escaped(n['name'])+'</title>'
    if kind=='hit':return ''
    if kind=='text':
        align={'left':'start','center':'middle','right':'end'}[n.get('align','left')]
        xx=x+(w/2 if align=='middle' else w if align=='end' else 0)
        spans=''.join(f'<tspan x="{xx}" y="{y+n["size"]*1.17+i*n["size"]*1.55}">{escaped(line)}</tspan>' for i,line in enumerate(n['text'].split('\n')))
        return f'<text font-family="Noto Sans JP,Noto Sans CJK JP,sans-serif" font-size="{n["size"]}" font-weight="{n["weight"]}" text-anchor="{align}" fill="{n["color"]}">{title}{spans}</text>'
    if kind=='icon':return f'<g transform="translate({x},{y}) scale({w/24},{h/24})">{title}<path d="{n["path"]}" fill="none" stroke="{n["color"]}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></g>'
    if kind=='ellipse':return f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w/2}" ry="{h/2}" fill="{n["fill"]}">{title}</ellipse>'
    stroke=f' stroke="{n["stroke"]}" stroke-width="1"' if n.get('stroke') else ''
    shape=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{n.get("radius",0)}" fill="{n.get("fill","none")}"{stroke}>{title}</rect>'
    if kind=='board':shape+=f'<g transform="translate({x},{y})">'+''.join(svg_node(c) for c in n.get('children',[]))+'</g>'
    return shape

def to_svg(s):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{s["w"]}" height="{s["h"]}" viewBox="0 0 {s["w"]} {s["h"]}" role="img" aria-label="{escaped(s["title"])}"><rect width="100%" height="100%" fill="{s["fill"]}"/>'+''.join(svg_node(n) for n in s['children'])+'</svg>'

def wrap_text(n):
    # Explicit wrapping keeps SVG proofs and editable Penpot text in agreement.
    if n.get('type')=='text':
        lines=[]
        for line in n['text'].split('\n'):
            buf='';units=0
            tokens=re.findall(r'[A-Za-z0-9_\-]+| +|[^A-Za-z0-9_\- ]',line)
            for token in tokens:
                cw=sum((.55 if ord(ch)<256 else 1)*n['size'] for ch in token)
                if units+cw>n['w'] and buf and token not in '。、.,:;!?':
                    lines.append(buf.rstrip());buf='';units=0
                if not buf:token=token.lstrip();cw=sum((.55 if ord(ch)<256 else 1)*n['size'] for ch in token)
                buf+=token;units+=cw
            lines.append(buf)
        n['text']='\n'.join(lines)
        n['weight']=round(n['weight']/100)*100
        n['h']=max(n['h'],math.ceil(n['size']*1.55)*len(lines))
    for c in n.get('children',[]):wrap_text(c)

def build():
    SCREENS.clear();build_primary();build_library();build_stats();build_settings();build_states();build_ipad();build_adaptive();build_foundations()
    counters={}
    for s in SCREENS:
        group=s['key'][0];i=counters.get(group,0);counters[group]=i+1
        if group=='M':s.update(x=(i%7)*497,y=(i//7)*1980)
        elif group=='I':s.update(x=3850+(i%3)*1500,y=(i//3)*1300)
        elif group in ['R','D']:s.update(x=8600+(i%2)*1550,y=(0 if group=='R' else 3400)+(i//2)*1550)
        else:s.update(x=(i%2)*1550,y=(i//2)*1280)
        wrap_text(s)
    return SCREENS

def gallery(screens):
    payload=json.dumps([{k:s[k] for k in ('key','title','w','h','theme')}|{'svg':to_svg(s)} for s in screens],ensure_ascii=False).replace('</','<\\/')
    return '''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
    *{box-sizing:border-box}body{margin:0;color:var(--foreground,#19253d);background:var(--background,#fff);font:14px system-ui,sans-serif}nav{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 16px}button,select{font:inherit;min-height:44px;border:1px solid var(--border,#dfe5ee);border-radius:9px;padding:8px 13px;background:var(--card,#f8fafc);color:inherit;cursor:pointer}button[aria-pressed=true]{background:#2563eb;color:#fff;border-color:#2563eb}select{width:100%;margin-bottom:16px}#stage{display:flex;justify-content:center;background:#e9edf4;border-radius:16px;overflow:hidden;padding:20px}#stage svg{display:block;max-width:100%;height:auto;box-shadow:0 10px 30px #14264915;border-radius:12px}#meta{font-size:12px;color:var(--muted-foreground,#65728a);margin:12px 0}.links{display:flex;gap:12px;flex-wrap:wrap;margin:12px 0}a{color:var(--accent,#2563eb)}@media(max-width:440px){#stage{padding:8px}button{padding:8px 10px}}
    </style><nav aria-label="表示する端末"><button data-group="M" aria-pressed="false">iPhone</button><button data-group="I" aria-pressed="true">iPad</button><button data-group="R" aria-pressed="false">可変幅</button><button data-group="D" aria-pressed="false">ダーク</button><button data-group="F" aria-pressed="false">設計仕様</button></nav><select id="screens" aria-label="画面を選択"></select><div id="stage"></div><p id="meta"></p><div class="links"><a href="https://design.penpot.app/#/workspace?file-id=3e981c57-46d6-803d-8008-bf1d62818b30&page-id=b16bcfc9-1baa-8054-8008-bf8ce0a6feaa" target="_blank" rel="noopener">Penpotで編集</a></div><script>const scenes='''+payload+''';let group='I';const select=document.querySelector('#screens');function draw(){let s=scenes.find(x=>x.key===select.value);document.querySelector('#stage').innerHTML=s.svg;document.querySelector('#stage svg').style.width=s.w+'px';document.querySelector('#meta').textContent=s.key+' · '+s.title+' · '+s.w+' × '+s.h+' pt / サンプルデータ';}function choose(g){group=g;select.innerHTML=scenes.filter(x=>x.key[0]===g).map(x=>'<option value="'+x.key+'">'+x.key+' · '+x.title+'</option>').join('');document.querySelectorAll('nav button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.group===g)));draw()}document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>choose(b.dataset.group));select.onchange=draw;choose('I');console.log('Design proofs:',scenes.length,'boards');</script></html>'''

def main():
    screens=build();out=ROOT/'generated';out.mkdir(exist_ok=True)
    for s in screens:(out/(s['key']+'.json')).write_text(json.dumps(s,ensure_ascii=False,separators=(',',':'))+'\n')
    (out/'manifest.json').write_text(json.dumps([dict(key=s['key'],title=s['title'],page=s['page'],w=s['w'],h=s['h']) for s in screens],ensure_ascii=False,indent=2)+'\n')
    (ROOT/'preview.html').write_text(gallery(screens))
    proofs=ROOT/'proofs';proofs.mkdir(exist_ok=True)
    for key in ['M01','M05','M13','M20','I01','I03','I04','I05','R01','R02','R03','R04','D01','D03']:
        s=next(s for s in screens if s['key']==key);(proofs/(key+'.svg')).write_text(to_svg(s))
    print(f'Built {len(screens)} boards, {len(json.dumps(screens)):,} bytes of editable scenes.')

if __name__=='__main__':main()
