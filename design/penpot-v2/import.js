/* Run through Penpot MCP execute_code, then call storage.fresh.importScreen(scene).
 * This importer only creates assets/pages prefixed Fresh / and never removes
 * earlier work. Credentials and external dependencies are not part of this file.
 */
storage.fresh = {
  pages: {}, boards: {}, tokens: {}, icons: {}, buttons: {}, links: [],
  async setup(data) {
    const ds = storage.fresh;
    ds.fileId = penpot.currentFile.id;
    ds.palette = data.tokens;
    ds.font = penpot.fonts.findByName('Noto Sans JP') || penpot.fonts.findByName('Noto Sans');
    if (!ds.font) throw new Error('A Japanese-capable design font must be selected.');
    for (const mode of ['light', 'dark']) {
      const set = penpot.library.local.tokens.addSet({name:'Fresh/'+mode, active:true});
      for (const [name, value] of Object.entries(data.tokens[mode]))
        ds.tokens[mode+'.'+name] = set.addToken({type:'color',name:'fresh.'+mode+'.'+name,value});
    }
    const foundation = penpot.createPage(); foundation.name='Fresh / 00 Foundations';
    ds.pages.foundation=foundation.id; await penpot.openPage(foundation);
    const board = penpot.createBoard(); board.name='F01 / Foundations & components';board.resize(1440,1380);board.fills=[{fillColor:'#F6F7FA',fillOpacity:1}];
    ds.foundation=board.id;
    ds.text(board,{x:40,y:36,w:1300,h:65,text:'negoto  /  記憶を、毎日の習慣に。',size:34,weight:600,fill:'#182337',align:'left'});
    ds.text(board,{x:40,y:102,w:1280,h:44,text:'Fresh design · iOS / iPadOS · AnkiMobile feature parity · 2026-10-06',size:16,weight:400,fill:'#637087',align:'left'});
    for (const [mi,mode] of ['light','dark'].entries()) {
      let i=0;
      for (const [name,value] of Object.entries(data.tokens[mode])) {
        const x=40+(i%9)*150,y=178+mi*224+Math.floor(i/9)*96;
        const r=penpot.createRectangle();r.name=mode+' / '+name;r.resize(130,44);r.borderRadius=10;board.appendChild(r);r.x=board.x+x;r.y=board.y+y;r.fills=[{fillColor:value,fillOpacity:1}];r.applyToken(ds.tokens[mode+'.'+name],['fill']);
        ds.text(board,{x,y:y+50,w:143,h:25,text:name+' '+value,size:10,weight:400,fill:'#637087',align:'left'});i++;
      }
    }
    ds.text(board,{x:40,y:646,w:1240,h:44,text:'Type · Large title 30 / Title 22 / Body 15–17 / Caption 11–13',size:22,weight:600,fill:'#182337',align:'left'});
    ds.text(board,{x:40,y:694,w:1240,h:80,text:'Spacing 4 · 8 · 12 · 16 · 20 · 24 · 32   /   Radius 12 · 14 · 18 · 22\nNative shipping: system fonts + SF Symbols. Penpot: Noto Sans JP + original vector icons.',size:15,weight:400,fill:'#637087',align:'left'});
    for (const [i,tone] of ['blue','tint','surface','redSoft','greenSoft','orangeSoft'].entries()) {
      const b=penpot.createBoard();b.name='Fresh / Button / '+tone;b.resize(196,48);b.borderRadius=14;b.fills=[{fillColor:data.tokens.light[tone],fillOpacity:1}];board.appendChild(b);b.x=board.x+40+(i%3)*222;b.y=board.y+815+Math.floor(i/3)*75;b.applyToken(ds.tokens['light.'+tone],['fill']);
      ds.text(b,{x:12,y:12,w:172,h:24,text:'続ける',size:15,weight:600,fill:tone==='blue'?'#FFFFFF':'#182337',align:'center'});
      const component=penpot.library.local.createComponent([b]);component.name='Button / '+tone;component.path='Fresh';ds.buttons[tone]=component.id;
    }
    ds.text(board,{x:40,y:1012,w:1280,h:90,text:'Responsive: <600 pt compact / 600–743 pt single workspace / 744–1023 pt sidebar / ≥1024 pt multiple panes\nTouch targets ≥44 pt · focus order · Dynamic Type · VoiceOver · reduced motion and transparency\nBreakpoints are application rules: Penpot boards document each state; the HTML prototype verifies the width transitions.',size:15,weight:400,fill:'#637087',align:'left'});
    ds.text(board,{x:40,y:1145,w:1260,h:100,text:'iOS / iPadOS 17+ fallback. Current Apple iOS/iPadOS 27 resources checked on 2026-10-06.\nNo Apple font binaries or UI kit files are redistributed. Charts and collection values are illustrative.\nStatic Penpot materials do not verify Liquid Glass or native device behavior.',size:14,weight:400,fill:'#637087',align:'left'});
    const layout=penpot.createBoard();layout.name='F02 / Resizable Flex layout';layout.resize(1040,350);layout.x=1520;layout.y=0;layout.fills=[{fillColor:'#EFF2F8',fillOpacity:1}];
    const flex=layout.addFlexLayout();flex.dir='row';flex.wrap='wrap';flex.alignItems='start';flex.columnGap=16;flex.rowGap=16;flex.topPadding=24;flex.leftPadding=24;flex.rightPadding=24;flex.bottomPadding=24;
    for(const [i,label] of ['回答回数','正答率','学習時間'].entries()){
      const cell=penpot.createBoard();cell.name='Metric / '+label;cell.resize(290,110);cell.borderRadius=18;cell.fills=[{fillColor:'#FFFFFF',fillOpacity:1}];layout.appendChild(cell);cell.layoutChild.horizontalSizing='fill';cell.layoutChild.minWidth=240;cell.layoutChild.maxWidth=440;
      ds.text(cell,{x:20,y:16,w:240,h:45,text:['1,248','92.4%','3.8時間'][i],size:28,weight:600,fill:'#182337',align:'left'});ds.text(cell,{x:20,y:68,w:240,h:25,text:label,size:13,weight:400,fill:'#637087',align:'left'});
    }
    // Store reusable icon components on the foundation page, not in screen roots.
    const unique=new Map();for(const s of data.screens)for(const n of s.nodes)if(n.kind==='icon')unique.set(n.name,n);
    let ii=0;for(const [name,n] of unique){
      const svg='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="'+n.path+'" fill="none" stroke="#637087" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      const icon=penpot.createShapeFromSvg(svg);icon.name=name;icon.x=1560+(ii%10)*72;icon.y=440+Math.floor(ii/10)*72;const comp=penpot.library.local.createComponent([icon]);comp.name=name;comp.path='Fresh';ds.icons[name]=comp.id;ii++;
    }
    for (const pageName of [...new Set(data.screens.map(s=>s.page))]) {
      const p=penpot.createPage();p.name='Fresh / '+pageName;ds.pages[pageName]=p.id;
    }
    return {fileId:ds.fileId,pages:ds.pages,font:ds.font.name,foundation:board.id};
  },
  text(parent,n) {
    const t=penpot.createText(n.text);storage.fresh.font.applyToText(t);
    t.name=n.name||n.text.slice(0,60);t.fontSize=String(n.size);t.fontWeight=String(n.weight||400);t.lineHeight='1.55';t.align=n.align||'left';t.verticalAlign='top';t.growType='fixed';t.resize(n.w,n.h);t.fills=[{fillColor:n.fill,fillOpacity:1}];parent.appendChild(t);t.x=parent.x+n.x;t.y=parent.y+n.y;t.constraintsHorizontal=n.align==='right'?'right':n.w>180?'leftright':'left';
    for(const mode of ['light','dark']){const found=Object.entries(storage.fresh.palette[mode]).find(([k,v])=>v.toLowerCase()===n.fill.toLowerCase());if(found){t.applyToken(storage.fresh.tokens[mode+'.'+found[0]],['fill']);break;}}
    return t;
  },
  async importScreen(s) {
    const ds=storage.fresh,pid=ds.pages[s.page];await penpot.openPage(pid);
    const siblings=Object.values(ds.boards).filter(b=>b.pageId===pid),large=s.page!=='01 iPhone',col=siblings.length%(large?3:6),row=Math.floor(siblings.length/(large?3:6));
    const existing=ds.boards[s.id];const b=existing?penpot.currentPage.getShapeById(existing.id):penpot.createBoard();
    if(existing){b.children.slice().forEach(c=>c.remove());if(b.flex)b.flex.remove();ds.links=ds.links.filter(l=>l.sourceScreen!==s.id);}
    b.name=s.id+' / '+s.title+' / '+s.width+'pt';b.resize(s.width,s.height);if(!existing){b.x=col*(large?1320:490);b.y=row*(s.page==='03 Adaptive'?1280:1060);}b.clipContent=true;b.fills=[{fillColor:ds.palette[s.dark?'dark':'light'].bg,fillOpacity:1}];b.applyToken(ds.tokens[(s.dark?'dark':'light')+'.bg'],['fill']);
    b.setPluginData('fresh-screen-id',s.id);b.setPluginData('responsive-contract',JSON.stringify({viewport:[s.width,s.height],compact:s.width<600,sidebar:s.width>=744,multiplePanes:s.width>=1024,tabbar:s.hasTabBar}));
    ds.boards[s.id]={id:b.id,pageId:pid,width:s.width,height:s.height,name:s.title};
    const shell=b.addFlexLayout();shell.dir='row';shell.wrap='nowrap';shell.columnGap=0;shell.rowGap=0;shell.alignItems='stretch';
    let sidebar=null;const hasSidebar=s.width>=744&&s.id!=='R07';
    if(hasSidebar){sidebar=penpot.createBoard();sidebar.name='Sidebar / fixed 232pt';sidebar.resize(232,s.height);sidebar.fills=[];b.appendChild(sidebar);sidebar.layoutChild.horizontalSizing='fix';sidebar.layoutChild.verticalSizing='fill';}
    const workspace=penpot.createBoard();workspace.name='Workspace / fill available width';workspace.resize(s.width-(hasSidebar?232:0),s.height);workspace.fills=[];b.appendChild(workspace);workspace.layoutChild.horizontalSizing='fill';workspace.layoutChild.verticalSizing='fill';workspace.x=b.x+(hasSidebar?232:0);workspace.y=b.y;
    const nodes=[];
    for(let i=1;i<s.nodes.length;i++) {
      const source=s.nodes[i];const parent=hasSidebar&&source.x<232?sidebar:workspace;
      const offset=parent===workspace&&hasSidebar?232:0;const n={...source,x:source.x-offset};let shape;
      if(n.kind==='text')shape=ds.text(parent,n);
      else if(n.kind==='icon') {
        const component=penpot.library.local.components.find(c=>c.id===ds.icons[n.name]);shape=component.instance();shape.name=n.name;shape.resize(n.w,n.h);parent.appendChild(shape);shape.x=parent.x+n.x;shape.y=parent.y+n.y;
        const tint=(sh)=>{if(sh.strokes?.length)sh.strokes=sh.strokes.map(st=>({...st,strokeColor:n.fill}));if(sh.children)sh.children.forEach(tint);};tint(shape);
      } else {
        shape=penpot.createRectangle();shape.name=n.name;shape.resize(n.w,n.h);shape.borderRadius=n.r||0;shape.fills=[{fillColor:n.fill,fillOpacity:1}];shape.opacity=n.opacity??1;
        if(n.stroke)shape.strokes=[{strokeColor:n.stroke,strokeWidth:1,strokeAlignment:'inner',strokeStyle:'solid',strokeOpacity:1}];
        parent.appendChild(shape);shape.x=parent.x+n.x;shape.y=parent.y+n.y;
      }
      if(n.token)shape.applyToken(ds.tokens[(s.dark?'dark':'light')+'.'+n.token],['fill']);
      shape.constraintsHorizontal=n.w>s.width*.7?'leftright':n.x>s.width*.75?'right':'left';
      if(n.y>=s.height-92&&s.hasTabBar){shape.constraintsVertical='bottom';shape.fixedWhenScrolling=true;}
      if(n.target)ds.links.push({source:shape.id,sourcePage:pid,sourceScreen:s.id,target:n.target});
      if(n.component)shape.setPluginData('component-role',n.component+' / '+n.tone);
      nodes.push(shape.id);
    }
    b.setPluginData('node-count',String(nodes.length));return ds.boards[s.id];
  },
  async link() {
    const ds=storage.fresh;let linked=0,missing=[];
    for(const [pageName,pageId] of Object.entries(ds.pages)) {
      if(pageName==='foundation')continue;await penpot.openPage(pageId);
      for(const l of ds.links.filter(l=>l.sourcePage===pageId)) {
        const dest=ds.boards[l.target];if(!dest){missing.push(l.target);continue;}
        const source=penpot.currentPage.getShapeById(l.source);const page=penpot.currentFile.pages.find(p=>p.id===dest.pageId);const board=page.getShapeById(dest.id);
        for(const old of source.interactions)source.removeInteraction(old);
        source.addInteraction('click',{type:'navigate-to',destination:board,preserveScrollPosition:false});linked++;
      }
      const first=Object.entries(ds.boards).find(([id,b])=>b.pageId===pageId);
      for(const flow of penpot.currentPage.flows.slice())if(flow.name==='Fresh / '+pageName)penpot.currentPage.removeFlow(flow);
      if(first)penpot.currentPage.createFlow('Fresh / '+pageName,penpot.currentPage.getShapeById(first[1].id));
    }
    return {linked,missing:[...new Set(missing)]};
  },
  async addHandoff() {
    const ds=storage.fresh;await penpot.openPage(ds.pages.foundation);
    const b=penpot.createBoard();b.name='F03 / Responsive behavior & handoff';b.resize(1440,1040);b.x=2700;b.y=0;b.fills=[{fillColor:'#F6F7FA',fillOpacity:1}];
    ds.text(b,{x:40,y:36,w:1360,h:60,text:'画面幅で切り替える、共通の設計ルール',size:30,weight:600,fill:'#182337'});
    ds.text(b,{x:40,y:110,w:1360,h:54,text:'iPhone / iPadの機種名ではなく、現在のウインドウのコンテンツ幅で判断。選択・検索語・編集中の内容を維持。',size:15,fill:'#637087'});
    const rows=[['320–599 pt','下部4タブ / 1列 / 余白20pt。ブラウズの詳細は次画面。統計は縦積み。'],['600–743 pt','1ペインを維持 / 余白32pt。フォームは中央寄せ。狭いiPadウインドウにも適用。'],['744–1023 pt','232ptサイドバー + 1ペイン。深い設定は最大640ptのフォーム、確認は最大560ptのシート。'],['1024 pt以上','一覧 + 詳細 / 編集 + プレビュー / 統計2列。デッキは学習パネル + カレンダー。'],['横向き・低い高さ','高さ500pt未満の学習ではカードを左、回答を右に配置。カード本文は独立してスクロール。']];
    rows.forEach(([label,value],i)=>{const y=200+i*100;ds.text(b,{x:40,y,w:220,h:50,text:label,size:19,weight:600,fill:'#245BDB'});ds.text(b,{x:285,y,w:1100,h:70,text:value,size:16,fill:'#182337'});});
    ds.text(b,{x:40,y:748,w:1360,h:104,text:'大きな文字：ラベルを折り返し、KPIを縦積み、回答を2×2または縦並びへ。\nキーボード：編集中フィールドへスクロール。書式バーをキーボード上へ。保存はナビゲーションに残す。\n44pt以上の操作領域 / VoiceOverの名前・順序 / フォーカス / Reduce Motion・Transparencyの代替を実装する。',size:15,fill:'#182337'});
    ds.text(b,{x:40,y:890,w:1360,h:105,text:'Penpotは各幅の状態とFlex・配置制約を記録。条件付きレイアウトの切り替えはHTMLプロトタイプで検証。\n画面：81 / 主要6画面 × 9幅で検証 / データはサンプル。実機・Penpot Viewの横断遷移は未検証。\n公式AnkiMobile公開仕様を基準。出典・機能対応表・再生成手順は design/penpot-v2/README.md。',size:14,fill:'#637087'});
    ds.handoff=b.id;
    for(const [name,size,weight] of [['Large title',30,600],['Title',22,600],['Headline',17,600],['Body',15,400],['Callout',13,400],['Caption',11,400]]){
      const style=penpot.library.local.createTypography();style.name=name;style.path='Fresh';style.setFont(ds.font);style.fontSize=String(size);style.fontWeight=String(weight);style.lineHeight='1.55';style.letterSpacing='0';
    }
    return {handoff:b.id,typographies:penpot.library.local.typographies.length};
  }
};
return {ready:true};
