// Run once through Penpot MCP execute_code. Then call:
// await storage.negoto.importScreen(scene), storage.negoto.linkAll().
// Native editable shapes, text, layouts, library colors, and prototype routes.
storage.negoto = storage.negoto || { screens: {}, links: [], pages: {}, assets: [] };
storage.negoto.make = function (n, parent, ox, oy) {
  let s;
  if (n.type === 'text') {
    s = penpot.createText(n.text);
    const font = penpot.fonts.all.find(f => f.name === 'Noto Sans JP');
    const weight = String(Math.round(n.weight / 100) * 100);
    if (font) font.applyToText(s, font.variants.find(v => v.fontWeight === weight && v.fontStyle === 'normal'));
    s.fontSize = String(n.size);
    s.fontWeight = weight;
    s.lineHeight = '1.55';
    s.align = n.align || 'left';
    s.verticalAlign = 'top';
    s.fills = [{ fillColor: n.color, fillOpacity: 1 }];
  } else if (n.type === 'icon') {
    s = penpot.createShapeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="${n.path}" fill="none" stroke="${n.color}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`);
  } else if (n.type === 'board') {
    s = penpot.createBoard();
    s.fills = n.fill ? [{ fillColor: n.fill, fillOpacity: 1 }] : [];
  } else if (n.type === 'ellipse') {
    s = penpot.createEllipse();
    s.fills = [{ fillColor: n.fill, fillOpacity: 1 }];
  } else {
    s = penpot.createRectangle();
    s.fills = n.type === 'hit' ? [{ fillColor: '#FFFFFF', fillOpacity: 0.001 }] : [{ fillColor: n.fill, fillOpacity: 1 }];
  }
  if (!s) throw new Error(`Failed to create ${n.name}`);
  s.name = n.name;
  s.resize(n.w, n.h);
  if (n.radius) s.borderRadius = n.radius;
  if (n.stroke) s.strokes = [{ strokeColor: n.stroke, strokeOpacity: 1, strokeWidth: 1, strokeStyle: 'solid', strokeAlignment: 'inner' }];
  if (parent) parent.appendChild(s);
  s.x = ox + n.x; s.y = oy + n.y;
  s.constraintsHorizontal = n.type === 'board' || n.type === 'text' ? 'leftright' : 'left';
  s.constraintsVertical = 'top';
  if (n.type === 'text') s.growType = 'fixed';
  for (const child of n.children || []) storage.negoto.make(child, s, s.x, s.y);
  if (n.layout) {
    const f = penpotUtils.addFlexLayout(s, n.layout.dir);
    f.alignItems = n.layout.alignItems;
    f.justifyContent = n.layout.justifyContent;
    f.columnGap = n.layout.gap || 0;
    f.rowGap = n.layout.gap || 0;
    f.horizontalSizing = 'fix'; f.verticalSizing = 'fix';
    for (const child of s.children) {
      child.layoutChild.horizontalSizing = 'fix';
      child.layoutChild.verticalSizing = 'fix';
    }
  }
  if (n.target) { s.setPluginData('negotoTarget', n.target); storage.negoto.links.push({ shape: s, target: n.target }); }
  if (n.external) s.addInteraction('click', { type: 'open-url', url: n.external });
  return s;
};
storage.negoto.importScreen = async function (scene) {
  let page = penpotUtils.getPageByName(scene.page);
  if (!page) { page = penpot.createPage(); page.name = scene.page; }
  await penpot.openPage(page);
  storage.negoto.pages[scene.page] = page.id;
  const existing = page.findShapes({ type: 'board' }).find(s => s.getPluginData('negotoKey') === scene.key);
  let hash = 2166136261;
  for (const ch of JSON.stringify(scene)) hash = Math.imul(hash ^ ch.charCodeAt(0), 16777619);
  const fingerprint = String(hash >>> 0);
  if (existing?.getPluginData('negotoComplete') === 'true' && existing.getPluginData('negotoHash') === fingerprint) { storage.negoto.screens[scene.key] = existing; return { key: scene.key, skipped: true, id: existing.id }; }
  if (existing) existing.remove(); // Only an incomplete board created by this importer.
  const b = penpot.createBoard(); b.name = scene.name;
  b.resize(scene.w, scene.h); b.x = scene.x; b.y = scene.y;
  b.fills = [{ fillColor: scene.fill, fillOpacity: 1 }];
  b.setPluginData('negotoKey', scene.key);
  b.setPluginData('negotoResponsive', scene.responsive || 'Compact: stacked; regular: sidebar and detail. See 00 Foundations.');
  for (const child of scene.children) storage.negoto.make(child, b, scene.x, scene.y);
  b.setPluginData('negotoComplete', 'true');
  b.setPluginData('negotoHash', fingerprint);
  storage.negoto.screens[scene.key] = b;
  return { key: scene.key, id: b.id, children: b.children.length };
};
storage.negoto.linkAll = function () {
  const missing = [];
  let count = 0;
  const hotspots = penpotUtils.findShapes(s => !!s.getPluginData('negotoTarget'));
  for (const shape of hotspots) {
    const target = shape.getPluginData('negotoTarget');
    const destination = storage.negoto.screens[target];
    if (!destination) { missing.push(target); continue; }
    for (const old of shape.interactions) shape.removeInteraction(old);
    shape.addInteraction('click', { type: 'navigate-to', destination, preserveScrollPosition: false });
    count++;
  }
  return { linked: count, missing: [...new Set(missing)] };
};
storage.negoto.addColors = function (colors) {
  for (const [name, value] of Object.entries(colors)) {
    if (penpot.library.local.colors.some(c => c.name === 'Negoto / ' + name)) continue;
    const color = penpot.library.local.createColor(); color.name = 'Negoto / ' + name; color.color = value;
  }
};
return { ready: true, fileId: penpot.currentFile.id };
