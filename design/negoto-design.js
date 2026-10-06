// Negoto redesign — generated with OpenPencil (Figma plugin API).
// Build: design/build.sh  →  design/Negoto.fig + design/exports/*.png
//
// The design follows Apple's Human Interface Guidelines for iOS / iPadOS 26:
// system colours and materials, SF-style type scale (Dynamic Type sizes), 44pt touch targets,
// tab bar on compact widths, floating sidebar (NavigationSplitView) on regular widths,
// inset-grouped lists, inspector on iPad, Liquid Glass only for the navigation / control layer.

const FAM = 'Noto Sans JP' // stands in for SF Pro + Hiragino Sans in mockups
for (const s of ['Regular', 'Medium', 'SemiBold', 'Bold']) await figma.loadFontAsync({ family: FAM, style: s })

// ───────────────────────── Tokens ─────────────────────────

const LIGHT = {
  name: 'Light',
  bg: '#F2F2F7', // systemGroupedBackground
  cell: '#FFFFFF', // secondarySystemGroupedBackground
  plain: '#FFFFFF', // systemBackground
  label: '#000000',
  secondary: '#3C3C4399',
  tertiary: '#3C3C434D',
  separator: '#C6C6C8',
  fill: '#7676801F', // tertiarySystemFill
  fill2: '#78788033',
  tint: '#007AFF', // systemBlue (accent)
  blue: '#007AFF',
  red: '#FF3B30',
  orange: '#FF9500',
  green: '#34C759',
  purple: '#AF52DE',
  teal: '#30B0C7',
  gray: '#8E8E93',
  glass: '#FFFFFFC7',
  glassStroke: '#FFFFFF99',
  dim: '#00000033',
  shadow: 0.1,
}
const DARK = {
  name: 'Dark',
  bg: '#000000',
  cell: '#1C1C1E',
  plain: '#000000',
  label: '#FFFFFF',
  secondary: '#EBEBF599',
  tertiary: '#EBEBF54D',
  separator: '#38383A',
  fill: '#7676803D',
  fill2: '#7878805C',
  tint: '#0A84FF',
  blue: '#0A84FF',
  red: '#FF453A',
  orange: '#FF9F0A',
  green: '#30D158',
  purple: '#BF5AF2',
  teal: '#40C8E0',
  gray: '#8E8E93',
  glass: '#2C2C2EC7',
  glassStroke: '#FFFFFF24',
  dim: '#00000080',
  shadow: 0.35,
}
let K = LIGHT

// ───────────────────────── Primitives ─────────────────────────

function hex(h) {
  h = h.replace('#', '')
  const n = (i) => parseInt(h.slice(i, i + 2), 16) / 255
  return { color: { r: n(0), g: n(2), b: n(4) }, a: h.length === 8 ? n(6) : 1 }
}
function paint(h, op = 1) {
  if (!h) return []
  const { color, a } = hex(h)
  return [{ type: 'SOLID', color, opacity: a * op }]
}
function shadow(y = 4, blur = 16, a = K.shadow) {
  return { type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a }, offset: { x: 0, y }, radius: blur, spread: 0, visible: true, blendMode: 'NORMAL' }
}

const WANT = new Map()
function want(n, o) {
  WANT.set(n, Object.assign(WANT.get(n) || {}, o))
  return n
}
function applyWant(k) {
  const w = WANT.get(k)
  if (!w) return
  if (w.abs) {
    k.layoutPositioning = 'ABSOLUTE'
    k.x = w.x
    k.y = w.y
  }
  if (w.w === 'fill') k.layoutSizingHorizontal = 'FILL'
  if (w.h === 'fill') k.layoutSizingVertical = 'FILL'
}

function charW(ch, size) {
  const c = ch.codePointAt(0)
  if (c >= 0x2e80) return size
  if (ch === ' ') return size * 0.27
  if ('il.,:;|!\'·'.includes(ch)) return size * 0.3
  if ('mwMW%'.includes(ch)) return size * 0.86
  if (ch >= 'A' && ch <= 'Z') return size * 0.66
  if (ch >= '0' && ch <= '9') return size * 0.58
  return size * 0.55
}
function measure(s, size, weight) {
  const k = (weight === 'Bold' || weight === 'SemiBold' ? 1.04 : 1) * 1.08
  return Math.max(...s.split('\n').map((l) => [...l].reduce((a, ch) => a + charW(ch, size), 0))) * k
}

/** Text. o: size, weight, color, w (number | 'fill'), lines, align, lh */
function txt(s, o = {}) {
  const size = o.size || 17
  const weight = o.weight || 'Regular'
  const t = figma.createText()
  t.fontName = { family: FAM, style: weight }
  t.characters = s
  t.fontSize = size
  t.fills = paint(o.color || K.label)
  const lh = o.lh || Math.round(size * 1.3)
  t.lineHeight = { value: lh, unit: 'PIXELS' }
  t.textAlignHorizontal = (o.align || 'left').toUpperCase()
  t.textAlignVertical = 'CENTER'
  let w = Math.ceil(measure(s, size, weight)) + 4
  let lines = o.lines || s.split('\n').length
  if (typeof o.w === 'number') {
    w = o.w
    if (!o.lines) lines = s.split('\n').reduce((a, l) => a + Math.max(1, Math.ceil(measure(l, size, weight) / o.w)), 0)
  }
  t.textAutoResize = 'NONE'
  t.resize(w, lh * lines)
  if (o.w === 'fill') want(t, { w: 'fill' })
  t.name = s.slice(0, 32)
  return t
}

/** Frame. dir: 'v' | 'h' | 'none'; w/h: number | 'fill' | undefined (hug) */
function box(o = {}, kids = []) {
  const f = figma.createFrame()
  f.name = o.name || 'box'
  f.fills = o.fill ? paint(o.fill) : []
  if (o.r != null) f.cornerRadius = o.r
  if (o.stroke) {
    f.strokes = paint(o.stroke)
    f.strokeWeight = o.sw || 1
    f.strokeAlign = 'INSIDE'
  }
  const fx = []
  if (o.shadow) fx.push(shadow(...(Array.isArray(o.shadow) ? o.shadow : [])))
  if (o.blur) fx.push({ type: 'BACKGROUND_BLUR', radius: o.blur, visible: true })
  if (fx.length) f.effects = fx
  f.clipsContent = !!o.clip
  const dir = o.dir || 'v'
  if (dir !== 'none') {
    f.layoutMode = dir === 'h' ? 'HORIZONTAL' : 'VERTICAL'
    f.itemSpacing = o.gap || 0
    const p = o.pad == null ? [0, 0, 0, 0] : typeof o.pad === 'number' ? [o.pad, o.pad, o.pad, o.pad] : o.pad.length === 2 ? [o.pad[0], o.pad[1], o.pad[0], o.pad[1]] : o.pad
    f.paddingTop = p[0]
    f.paddingRight = p[1]
    f.paddingBottom = p[2]
    f.paddingLeft = p[3]
    f.primaryAxisAlignItems = { start: 'MIN', center: 'CENTER', end: 'MAX', between: 'SPACE_BETWEEN' }[o.justify || 'start']
    f.counterAxisAlignItems = { start: 'MIN', center: 'CENTER', end: 'MAX' }[o.align || (dir === 'h' ? 'center' : 'start')]
  }
  f.resize(typeof o.w === 'number' ? o.w : 10, typeof o.h === 'number' ? o.h : 10)
  for (const k of kids.flat(3)) {
    if (!k) continue
    f.appendChild(k)
    applyWant(k)
  }
  if (dir !== 'none') {
    f.layoutSizingHorizontal = typeof o.w === 'number' ? 'FIXED' : 'HUG'
    f.layoutSizingVertical = typeof o.h === 'number' ? 'FIXED' : 'HUG'
  }
  if (o.w === 'fill') want(f, { w: 'fill' })
  if (o.h === 'fill') want(f, { h: 'fill' })
  if (o.x != null) f.x = o.x
  if (o.y != null) f.y = o.y
  if (o.opacity != null) f.opacity = o.opacity
  return f
}
const hs = (o, kids) => box({ ...o, dir: 'h' }, kids)
const vs = (o, kids) => box({ ...o, dir: 'v' }, kids)
const spacer = (h = 1) => box({ dir: 'none', w: 'fill', h, name: 'spacer' })
const gap = (h) => box({ dir: 'none', w: 1, h, name: 'gap' })
/** Places a node absolutely inside a non-auto-layout parent. */
function place(parent, node, x, y) {
  parent.appendChild(node)
  node.x = x
  node.y = y
  return node
}

function rect(w, h, color, r = 0) {
  const n = figma.createRectangle()
  n.resize(w, h)
  n.fills = paint(color)
  n.cornerRadius = r
  return n
}
function line(w, color = K.separator, h = 0.5) {
  const n = rect(w === 'fill' ? 10 : w, h, color)
  n.name = 'separator'
  if (w === 'fill') want(n, { w: 'fill' })
  return n
}

// ───────────────────────── Icons (SF Symbols stand-ins) ─────────────────────────

const ICONS = {
  'chevron.right': [{ d: 'M 9 5 L 16 12 L 9 19' }],
  'chevron.left': [{ d: 'M 15 4.5 L 7.5 12 L 15 19.5' }],
  'chevron.down': [{ d: 'M 6 9 L 12 15 L 18 9' }],
  'chevron.up.down': [{ d: 'M 7.5 9.5 L 12 5 L 16.5 9.5 M 7.5 14.5 L 12 19 L 16.5 14.5' }],
  plus: [{ d: 'M 12 4.5 L 12 19.5 M 4.5 12 L 19.5 12' }],
  xmark: [{ d: 'M 6 6 L 18 18 M 18 6 L 6 18' }],
  checkmark: [{ d: 'M 4.5 12.5 L 9.5 17.5 L 19.5 6.5' }],
  magnifyingglass: [{ ellipse: [3.5, 3.5, 13, 13] }, { d: 'M 14.6 14.6 L 20.5 20.5' }],
  ellipsis: [{ ellipse: [3.2, 10.2, 3.6, 3.6], fill: true }, { ellipse: [10.2, 10.2, 3.6, 3.6], fill: true }, { ellipse: [17.2, 10.2, 3.6, 3.6], fill: true }],
  sync: [{ d: 'M 4 12 C 4 7.6 7.6 4 12 4 C 14.8 4 17.2 5.4 18.6 7.6 M 19.2 3.6 L 19.2 8.2 L 14.6 8.2 M 20 12 C 20 16.4 16.4 20 12 20 C 9.2 20 6.8 18.6 5.4 16.4 M 4.8 20.4 L 4.8 15.8 L 9.4 15.8' }],
  undo: [{ d: 'M 8.5 13.5 L 4 9 L 8.5 4.5 M 4 9 L 15 9 C 18 9 20.5 11.4 20.5 14.5 C 20.5 17.6 18 20 15 20 L 10 20' }],
  flag: [{ d: 'M 5.5 21 L 5.5 3.5 M 5.5 4 C 9 2 12 6 18.5 4 L 18.5 13 C 12 15 9 11 5.5 13' }],
  'flag.fill': [{ d: 'M 5.5 4 C 9 2 12 6 18.5 4 L 18.5 13 C 12 15 9 11 5.5 13 Z', fill: true }, { d: 'M 5.5 21 L 5.5 3.5' }],
  info: [{ ellipse: [2.5, 2.5, 19, 19] }, { d: 'M 12 10.8 L 12 17' }, { ellipse: [10.8, 6.4, 2.4, 2.4], fill: true }],
  sidebar: [{ rect: [2.5, 4.5, 19, 15, 3.5] }, { d: 'M 9 4.5 L 9 19.5' }],
  'sidebar.right': [{ rect: [2.5, 4.5, 19, 15, 3.5] }, { d: 'M 15 4.5 L 15 19.5' }],
  decks: [{ rect: [7, 3, 14, 12, 2.5] }, { d: 'M 3.5 7.5 L 3.5 17.5 C 3.5 19.4 4.6 20.5 6.5 20.5 L 16.5 20.5' }],
  'decks.fill': [{ rect: [7, 3, 14, 12, 2.5], fill: true }, { d: 'M 3.5 7.5 L 3.5 17.5 C 3.5 19.4 4.6 20.5 6.5 20.5 L 16.5 20.5' }],
  list: [{ ellipse: [3.2, 4.7, 2.6, 2.6], fill: true }, { ellipse: [3.2, 10.7, 2.6, 2.6], fill: true }, { ellipse: [3.2, 16.7, 2.6, 2.6], fill: true }, { d: 'M 9 6 L 20.5 6 M 9 12 L 20.5 12 M 9 18 L 20.5 18' }],
  chart: [{ rect: [3.5, 13, 4, 7.5, 1.2], fill: true }, { rect: [10, 8, 4, 12.5, 1.2], fill: true }, { rect: [16.5, 3.5, 4, 17, 1.2], fill: true }],
  gear: [{ ellipse: [6, 6, 12, 12] }, { ellipse: [9.6, 9.6, 4.8, 4.8] }, { d: 'M 12 2.5 L 12 6 M 12 18 L 12 21.5 M 2.5 12 L 6 12 M 18 12 L 21.5 12 M 5.3 5.3 L 7.8 7.8 M 16.2 16.2 L 18.7 18.7 M 5.3 18.7 L 7.8 16.2 M 16.2 7.8 L 18.7 5.3' }],
  filter: [{ d: 'M 4 7 L 20 7 M 7 12 L 17 12 M 10 17 L 14 17' }],
  'filter.circle': [{ ellipse: [2.5, 2.5, 19, 19] }, { d: 'M 7 9 L 17 9 M 9 12.5 L 15 12.5 M 11 16 L 13 16' }],
  speaker: [{ d: 'M 3.5 9 L 3.5 15 L 7.5 15 L 12.5 19 L 12.5 5 L 7.5 9 Z' }, { d: 'M 16 9 C 17.2 10.4 17.2 13.6 16 15 M 18.8 6.5 C 21.6 9.4 21.6 14.6 18.8 17.5' }],
  pencil: [{ d: 'M 4 20 L 5 15.5 L 16 4.5 L 19.5 8 L 8.5 19 Z M 13.8 6.7 L 17.3 10.2' }],
  play: [{ d: 'M 7 4.5 L 19 12 L 7 19.5 Z', fill: true }],
  tag: [{ d: 'M 3.5 11.5 L 11.5 3.5 L 19.8 3.5 C 20.2 3.5 20.5 3.8 20.5 4.2 L 20.5 12.5 L 12.5 20.5 Z' }, { ellipse: [15, 7, 2.4, 2.4], fill: true }],
  calendar: [{ rect: [3.5, 5, 17, 15.5, 3] }, { d: 'M 3.5 10 L 20.5 10 M 8 3 L 8 7 M 16 3 L 16 7' }],
  sun: [{ ellipse: [7.5, 7.5, 9, 9] }, { d: 'M 12 1.8 L 12 4.2 M 12 19.8 L 12 22.2 M 1.8 12 L 4.2 12 M 19.8 12 L 22.2 12 M 4.8 4.8 L 6.5 6.5 M 17.5 17.5 L 19.2 19.2 M 4.8 19.2 L 6.5 17.5 M 17.5 6.5 L 19.2 4.8' }],
  photo: [{ rect: [2.5, 4.5, 19, 15, 3] }, { d: 'M 3 17 L 8.5 11.5 L 12.5 15.5 L 15 13 L 21 18.5' }, { ellipse: [14.5, 7.5, 3, 3], fill: true }],
  sort: [{ d: 'M 8 20 L 8 4 M 4 8 L 8 4 L 12 8 M 16 4 L 16 20 M 12 16 L 16 20 L 20 16' }],
  tray: [{ d: 'M 12 3 L 12 14 M 7.5 9.5 L 12 14 L 16.5 9.5 M 3.5 13.5 L 3.5 18 C 3.5 19.4 4.6 20.5 6 20.5 L 18 20.5 C 19.4 20.5 20.5 19.4 20.5 18 L 20.5 13.5' }],
  icloud: [{ d: 'M 7 18.5 L 17.5 18.5 C 20 18.5 21.5 16.7 21.5 14.5 C 21.5 12.3 19.8 10.7 17.8 10.7 C 17.2 7.7 14.8 6 12 6 C 9 6 6.6 8.1 6.2 10.9 C 4.2 11.3 2.5 12.9 2.5 14.9 C 2.5 16.9 4.4 18.5 7 18.5 Z', fill: true }],
  hand: [{ d: 'M 8 13 L 8 5.5 C 8 4.7 8.7 4 9.5 4 C 10.3 4 11 4.7 11 5.5 L 11 11 M 11 10 L 11 3.8 C 11 3 11.7 2.3 12.5 2.3 C 13.3 2.3 14 3 14 3.8 L 14 10 M 14 10 L 14 5 C 14 4.2 14.7 3.5 15.5 3.5 C 16.3 3.5 17 4.2 17 5 L 17 14 C 17 18 14.5 21 11 21 C 8 21 6.5 19 5 16 L 3.5 12.8 C 3.1 12 3.5 11.1 4.3 10.8 C 5 10.5 5.8 10.9 6.2 11.6 L 8 15' }],
  textsize: [{ d: 'M 3 8 L 3 5.5 L 13 5.5 L 13 8 M 8 5.5 L 8 19 M 13 12 L 13 10.5 L 21 10.5 L 21 12 M 17 10.5 L 17 19' }],
  bold: [{ d: 'M 7 4.5 L 13 4.5 C 15.5 4.5 17 5.8 17 7.8 C 17 9.8 15.5 11.2 13 11.2 L 7 11.2 Z M 7 11.2 L 14 11.2 C 16.6 11.2 18 12.7 18 14.8 C 18 17 16.6 18.5 14 18.5 L 7 18.5 Z' }],
  italic: [{ d: 'M 10 4.5 L 18 4.5 M 6 19.5 L 14 19.5 M 14.5 4.5 L 9.5 19.5' }],
  underline: [{ d: 'M 7 4 L 7 11 C 7 14 9 16 12 16 C 15 16 17 14 17 11 L 17 4 M 5.5 20 L 18.5 20' }],
  moon: [{ d: 'M 19.5 14.5 C 18.5 15 17.3 15.3 16 15.3 C 11.6 15.3 8.2 11.9 8.2 7.5 C 8.2 6 8.6 4.6 9.4 3.5 C 5.6 4.5 2.9 8 2.9 12 C 2.9 16.9 6.8 20.8 11.7 20.8 C 15.3 20.8 18.4 18.4 19.5 14.5 Z' }],
  pause: [{ ellipse: [2.5, 2.5, 19, 19] }, { d: 'M 9.8 8.5 L 9.8 15.5 M 14.2 8.5 L 14.2 15.5' }],
  star: [{ d: 'M 12 3 L 14.6 8.8 L 20.6 9.3 L 16 13.3 L 17.4 19.5 L 12 16.2 L 6.6 19.5 L 8 13.3 L 3.4 9.3 L 9.4 8.8 Z' }],
  share: [{ d: 'M 12 3 L 12 15 M 8 7 L 12 3 L 16 7 M 8 10 L 6 10 C 5.2 10 4.5 10.7 4.5 11.5 L 4.5 19.5 C 4.5 20.3 5.2 21 6 21 L 18 21 C 18.8 21 19.5 20.3 19.5 19.5 L 19.5 11.5 C 19.5 10.7 18.8 10 18 10 L 16 10' }],
  bell: [{ d: 'M 6 16.5 L 6 11 C 6 7.7 8.7 5 12 5 C 15.3 5 18 7.7 18 11 L 18 16.5 L 19.5 18 L 4.5 18 Z M 10 20.5 L 14 20.5' }],
  paintbrush: [{ d: 'M 20 4 L 11 13 M 11 13 C 9 13 7.5 14.5 7.5 16.5 C 7.5 18.5 6 19.5 4 19.5 C 6 21.5 11 21.5 12.5 17.5 C 13 15.5 12.5 14 11 13' }],
  keyboard: [{ rect: [2.5, 6, 19, 12.5, 2.5] }, { d: 'M 6 9.5 L 7 9.5 M 9.5 9.5 L 10.5 9.5 M 13.5 9.5 L 14.5 9.5 M 17 9.5 L 18 9.5 M 6 12.5 L 7 12.5 M 17 12.5 L 18 12.5 M 8.5 15.5 L 15.5 15.5' }],
  doc: [{ d: 'M 6 3 L 14 3 L 19 8 L 19 20 C 19 20.6 18.6 21 18 21 L 6 21 C 5.4 21 5 20.6 5 20 L 5 4 C 5 3.4 5.4 3 6 3 Z M 14 3 L 14 8 L 19 8' }],
  wand: [{ d: 'M 4 20 L 15 9 M 13.5 7.5 L 16.5 10.5 M 17 3 L 17.6 4.6 L 19.2 5.2 L 17.6 5.8 L 17 7.4 L 16.4 5.8 L 14.8 5.2 L 16.4 4.6 Z M 20 10 L 20.4 11 L 21.4 11.4 L 20.4 11.8 L 20 12.8 L 19.6 11.8 L 18.6 11.4 L 19.6 11 Z' }],
  trash: [{ d: 'M 4 6.5 L 20 6.5 M 9.5 6.5 L 9.5 4.5 C 9.5 3.9 9.9 3.5 10.5 3.5 L 13.5 3.5 C 14.1 3.5 14.5 3.9 14.5 4.5 L 14.5 6.5 M 6 6.5 L 7 19.5 C 7.1 20.3 7.7 21 8.5 21 L 15.5 21 C 16.3 21 16.9 20.3 17 19.5 L 18 6.5 M 10 10.5 L 10.5 17 M 14 10.5 L 13.5 17' }],
  folder: [{ d: 'M 3 7 C 3 5.9 3.9 5 5 5 L 9.5 5 L 11.5 7 L 19 7 C 20.1 7 21 7.9 21 9 L 21 17.5 C 21 18.6 20.1 19.5 19 19.5 L 5 19.5 C 3.9 19.5 3 18.6 3 17.5 Z' }],
}

function scalePath(d, s) {
  return d.replace(/-?\d*\.?\d+/g, (n) => (parseFloat(n) * s).toFixed(2))
}

function icon(name, size = 22, color = K.label, weight = 1.9) {
  const s = size / 24
  const f = box({ dir: 'none', w: size, h: size, name: 'icon/' + name })
  for (const p of ICONS[name] || []) {
    let n
    if (p.d) {
      n = figma.createVector()
      n.vectorPaths = [{ windingRule: 'NONZERO', data: scalePath(p.d, s) }]
      n.resize(size, size)
    } else if (p.ellipse) {
      n = figma.createEllipse()
      n.resize(p.ellipse[2] * s, p.ellipse[3] * s)
      n.x = p.ellipse[0] * s
      n.y = p.ellipse[1] * s
    } else if (p.rect) {
      n = figma.createRectangle()
      n.resize(p.rect[2] * s, p.rect[3] * s)
      n.x = p.rect[0] * s
      n.y = p.rect[1] * s
      n.cornerRadius = p.rect[4] * s
    }
    if (p.fill) {
      n.fills = paint(color)
      n.strokes = []
    } else {
      n.fills = []
      n.strokes = paint(color)
      n.strokeWeight = weight * Math.max(0.75, s)
      n.strokeCap = 'ROUND'
      n.strokeJoin = 'ROUND'
    }
    f.appendChild(n)
    if (p.d) {
      n.x = 0
      n.y = 0
    }
  }
  return f
}

// ───────────────────────── Components ─────────────────────────

function glassCircle(name, o = {}) {
  const size = o.size || 44
  return box({ dir: 'h', w: size, h: size, r: size / 2, fill: o.fill || K.glass, stroke: o.fill ? null : K.glassStroke, shadow: o.fill ? null : [2, 10, K.shadow * 0.6], justify: 'center', align: 'center', name: 'glass/' + name }, [
    icon(name, o.icon || 20, o.color || K.label, 2),
  ])
}
function glassGroup(names, o = {}) {
  return hs({ h: 44, r: 22, fill: K.glass, stroke: K.glassStroke, shadow: [2, 10, K.shadow * 0.6], pad: [0, 4], name: 'glass/group' }, names.map((n) =>
    typeof n === 'string' ? box({ dir: 'h', w: 40, h: 44, justify: 'center', align: 'center' }, [icon(n, 20, o.color || K.label, 2)]) : n
  ))
}
function prominentCircle(name, color = K.tint) {
  return box({ dir: 'h', w: 44, h: 44, r: 22, fill: color, justify: 'center', align: 'center', name: 'prominent/' + name }, [icon(name, 20, '#FFFFFF', 2.4)])
}

function statusBar(w, pad = false, dark = K === DARK) {
  const c = K.label
  const f = box({ dir: 'none', w, h: pad ? 24 : 54, name: 'Status Bar' })
  if (pad) {
    place(f, txt('9:41  10月6日(火)', { size: 13, weight: 'SemiBold', color: c }), 22, 4)
  } else {
    place(f, txt('9:41', { size: 17, weight: 'SemiBold', color: c, w: 54, align: 'center' }), 48, 17)
  }
  // signal / wifi / battery
  const right = hs({ gap: 6, name: 'indicators' }, [
    hs({ gap: 2, align: 'end' }, [3, 5, 7, 9].map((h) => rect(3, h, c, 1))),
    box({ dir: 'none', w: 27, h: 13, r: 4, stroke: K.tertiary, name: 'battery' }, [Object.assign(rect(21, 9, c, 2), { x: 3, y: 2 })]),
  ])
  place(f, right, w - (pad ? 92 : 104), pad ? 6 : 22)
  return f
}
function homeIndicator(frame, w, h) {
  place(frame, rect(pad(w) ? 320 : 140, 5, K.label, 3), w / 2 - (pad(w) ? 160 : 70), h - 12)
}
const pad = (w) => w > 700

/** iOS 26 floating tab bar */
function tabBar(w, selected, items = TABS) {
  const iw = (w - 50) / items.length
  return hs({ w: w - 42, h: 62, r: 31, fill: K.glass, stroke: K.glassStroke, shadow: [4, 20, K.shadow], pad: [0, 4], name: 'Tab Bar' },
    items.map(([ic, label], i) => {
      const on = i === selected
      return vs({ w: iw, h: 54, r: 27, fill: on ? K.fill : null, align: 'center', justify: 'center', gap: 1 }, [
        icon(on && ICONS[ic + '.fill'] ? ic + '.fill' : ic, 24, on ? K.tint : K.label, 1.9),
        txt(label, { size: 10, weight: 'SemiBold', color: on ? K.tint : K.label }),
      ])
    }))
}
const TABS = [['decks', 'デッキ'], ['list', 'ブラウズ'], ['chart', '統計'], ['gear', '設定']]

function largeTitle(s, w) {
  return box({ dir: 'h', w, h: 52, pad: [0, 16], align: 'end', name: 'Large Title' }, [txt(s, { size: 34, weight: 'Bold', lh: 41 })])
}

function searchField(w, value, placeholder = '検索') {
  return hs({ w, h: 40, r: 20, fill: K.fill, pad: [0, 12], gap: 6, name: 'Search Field' }, [
    icon('magnifyingglass', 17, K.secondary, 2),
    txt(value || placeholder, { size: 17, color: value ? K.label : K.secondary, w: 'fill' }),
    value ? box({ dir: 'h', w: 18, h: 18, r: 9, fill: K.gray, justify: 'center' }, [icon('xmark', 10, K.cell, 2.6)]) : null,
  ])
}

/** Inset-grouped section. rows: nodes (each full width). */
function section(w, header, rows, o = {}) {
  const inner = []
  rows.forEach((r, i) => {
    inner.push(r)
    if (i < rows.length - 1 && !o.noSeparators) inner.push(hs({ w: 'fill', pad: [0, 0, 0, o.inset ?? 20] }, [line('fill')]))
  })
  return vs({ w, gap: 7, pad: [0, 16], name: 'Section ' + (header || '') }, [
    header ? hs({ w: 'fill', pad: [0, 20], justify: 'between', align: 'end' }, [txt(header, { size: 15, weight: 'SemiBold', color: o.headerColor || K.label }), o.headerAccessory || null]) : null,
    vs({ w: 'fill', r: 26, fill: o.fill || K.cell, clip: true, pad: o.inner || 0 }, inner),
    o.footer ? hs({ w: 'fill', pad: [0, 20] }, [txt(o.footer, { size: 13, color: K.secondary, w: w - 72 })]) : null,
  ])
}

/** A standard list row: [icon] title [subtitle] … detail [accessory] */
function row(title, o = {}) {
  const left = []
  if (o.iconSquare) left.push(box({ dir: 'h', w: 30, h: 30, r: 8, fill: o.iconSquare[1], justify: 'center' }, [icon(o.iconSquare[0], 18, '#FFFFFF', 2)]))
  if (o.icon) left.push(icon(o.icon, 22, o.iconColor || K.tint))
  if (o.dot) left.push(box({ dir: 'h', w: 22, h: 22, justify: 'center' }, [box({ dir: 'none', w: 10, h: 10, r: 5, fill: o.dot })]))
  const titleBlock = o.subtitle
    ? vs({ w: 'fill', gap: 1 }, [txt(title, { size: 17, weight: o.weight, color: o.titleColor || K.label, w: 'fill' }), txt(o.subtitle, { size: 13, color: K.secondary, w: 'fill' })])
    : txt(title, { size: 17, weight: o.weight, color: o.titleColor || K.label, w: 'fill' })
  return hs({ w: 'fill', h: o.h || (o.subtitle ? 62 : 52), pad: [0, 20, 0, o.indent ?? 20], gap: 12, fill: o.selected ? K.fill : null, name: 'Row ' + title }, [
    ...left,
    titleBlock,
    o.trailing || null,
    o.detail != null ? txt(o.detail, { size: 17, color: K.secondary }) : null,
    o.toggle != null ? toggle(o.toggle) : null,
    o.chevron ? icon('chevron.right', 14, K.tertiary, 2.6) : null,
    o.menu ? icon('chevron.up.down', 14, K.secondary, 2.4) : null,
  ])
}
function toggle(on) {
  const f = box({ dir: 'none', w: 63, h: 28, r: 14, fill: on ? K.green : K.fill2, name: 'Toggle' })
  place(f, box({ dir: 'none', w: 37, h: 24, r: 12, fill: '#FFFFFF', shadow: [1, 4, 0.15] }), on ? 24 : 2, 2)
  return f
}

/** Anki's new · learning · review counts, right-aligned columns. */
function counts(n, l, r, size = 15) {
  const one = (v, c) => txt(String(v), { size, weight: 'SemiBold', color: v > 0 ? c : K.tertiary, w: 30, align: 'right' })
  return hs({ gap: 4, name: 'Counts' }, [one(n, K.blue), one(l, K.red), one(r, K.green)])
}

function button(label, o = {}) {
  const prominent = o.style !== 'tinted' && o.style !== 'plain'
  const color = o.color || K.tint
  return hs({ w: o.w || 'fill', h: o.h || 50, r: (o.h || 50) / 2, fill: prominent ? color : o.style === 'plain' ? null : color + '26', justify: 'center', gap: 8, name: 'Button ' + label }, [
    o.icon ? icon(o.icon, 18, prominent ? '#FFFFFF' : color, 2.2) : null,
    txt(label, { size: o.size || 17, weight: 'SemiBold', color: prominent ? '#FFFFFF' : color }),
  ])
}

function segmented(w, items, sel, h = 32) {
  const iw = (w - 4) / items.length
  return hs({ w, h, r: h / 2, fill: K.fill, pad: 2, name: 'Segmented' }, items.map((s, i) =>
    hs({ w: iw, h: h - 4, r: (h - 4) / 2, fill: i === sel ? (K === DARK ? '#636366' : '#FFFFFF') : null, shadow: i === sel ? [2, 6, 0.08] : null, justify: 'center' }, [
      txt(s, { size: 13, weight: i === sel ? 'SemiBold' : 'Medium' }),
    ])))
}

function chip(title, value, o = {}) {
  return hs({ h: 34, r: 17, fill: o.active ? K.tint + '1F' : K.cell, stroke: o.active ? null : K.separator, pad: [0, 12], gap: 4, name: 'Chip ' + title }, [
    txt(title, { size: 13, weight: 'Medium', color: o.active ? K.tint : K.secondary }),
    value ? txt(value, { size: 13, weight: 'SemiBold', color: o.active ? K.tint : K.label }) : null,
    icon('chevron.down', 11, o.active ? K.tint : K.secondary, 2.6),
  ])
}

function bars(values, o = {}) {
  const max = Math.max(1, ...values)
  const h = o.h || 110
  const bw = o.bw || 22
  return hs({ w: o.w || 'fill', h: h + 36, justify: 'between', align: 'end', name: 'Bar Chart' }, values.map((v, i) =>
    vs({ w: bw + 8, align: 'center', gap: 4 }, [
      txt(String(v), { size: 11, weight: 'Medium', color: K.secondary }),
      rect(bw, Math.max(4, (v / max) * h), i === 0 ? K.tint : K.tint + '55', 5),
      txt(o.labels ? o.labels[i] : '', { size: 11, color: K.secondary }),
    ])))
}

/** Statistics card (opaque content block). */
function statCard(w, title, kids, o = {}) {
  return vs({ w, r: 26, fill: K.cell, pad: 18, gap: 14, name: 'Stat ' + title }, [
    hs({ w: 'fill', gap: 8, align: 'center' }, [txt(title, { size: 17, weight: 'SemiBold' }), o.badge ? txt(o.badge, { size: 13, weight: 'SemiBold', color: K.tint }) : null, spacer(), o.accessory || null]),
    ...kids,
  ])
}
function metric(value, unit, caption, color = K.label, size = 28) {
  return vs({ gap: 0 }, [
    hs({ gap: 2, align: 'end' }, [txt(value, { size, weight: 'Bold', color, lh: Math.round(size * 1.15) }), unit ? txt(unit, { size: 13, weight: 'Medium', color: K.secondary }) : null]),
    txt(caption, { size: 13, color: K.secondary }),
  ])
}

function heatmap(weeks, cell = 11) {
  const cols = []
  let seed = 7
  const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280)
  for (let w = 0; w < weeks; w++) {
    cols.push(vs({ gap: 3 }, Array.from({ length: 7 }, (_, d) => {
      const v = rnd()
      const recent = w > weeks * 0.35
      const level = !recent && v < 0.6 ? 0 : v < 0.25 ? 0 : v < 0.5 ? 1 : v < 0.75 ? 2 : 3
      const future = w === weeks - 1 && d > 1
      return rect(cell, cell, future ? '#00000000' : level === 0 ? K.fill : K.tint + ['', '55', '99', 'FF'][level], 3)
    })))
  }
  return hs({ gap: 3, name: 'Heatmap' }, cols)
}

function answerButton(rating, interval, w, h = 56) {
  const map = { again: ['もう一度', K.red], hard: ['難しい', K.orange], good: ['普通', K.green], easy: ['簡単', K.blue] }
  const [label, color] = map[rating]
  return vs({ w, h, r: 18, fill: color + (K === DARK ? '33' : '1F'), justify: 'center', align: 'center', gap: 0, name: 'Answer ' + label }, [
    txt(interval, { size: 12, weight: 'SemiBold', color }),
    txt(label, { size: 16, weight: 'Bold', color }),
  ])
}

function cardContent(w, answer, o = {}) {
  const big = o.big || 38
  return vs({ w, align: 'center', gap: 14, pad: [o.top || 64, 24, 24, 24], name: 'Card (WKWebView)' }, [
    txt('ubiquitous', { size: big, weight: 'Bold', align: 'center', w: w - 48 }),
    answer ? line(w * 0.7, K.separator, 1) : null,
    answer ? txt('どこにでもある、遍在する', { size: 24, weight: 'Medium', align: 'center', w: w - 48 }) : null,
    answer ? txt('/juːˈbɪkwɪtəs/', { size: 17, color: K.secondary, align: 'center', w: w - 48 }) : null,
    answer ? txt('Smartphones have become ubiquitous.\nスマートフォンはどこにでもあるものになった。', { size: 15, color: K.secondary, align: 'center', w: Math.min(w - 48, 520), lh: 22 }) : null,
  ])
}

// ───────────────────────── Sample data ─────────────────────────

const DECKS = [
  { name: '英単語 TOEIC', n: 20, l: 3, r: 48, color: 'blue' },
  { name: '日本史', n: 10, l: 0, r: 12, color: 'orange', kids: [{ name: '古代', n: 5, l: 0, r: 4 }, { name: '中世', n: 5, l: 0, r: 8 }] },
  { name: 'Math & Science', n: 5, l: 0, r: 0, color: 'purple' },
  { name: '化学 元素記号', n: 0, l: 0, r: 0, color: 'teal' },
]
const TOTAL = { n: 35, l: 3, r: 60 }

// ───────────────────────── Screens ─────────────────────────

function screen(name, w, h, bg = K.bg) {
  const f = box({ dir: 'none', w, h, fill: bg, clip: true, name })
  f.cornerRadius = w > 700 ? 18 : 48
  return f
}

function deckRows(o = {}) {
  const rows = []
  for (const d of DECKS) {
    rows.push(deckRow(d, 0, o))
    if (d.kids && !o.collapsed) for (const k of d.kids) rows.push(deckRow(k, 1, o))
  }
  return rows
}
function deckRow(d, depth, o = {}) {
  const lead = d.kids
    ? box({ dir: 'h', w: 22, h: 22, justify: 'center' }, [icon('chevron.down', 13, K.secondary, 2.6)])
    : box({ dir: 'h', w: 22, h: 22, justify: 'center' }, [box({ dir: 'none', w: 9, h: 9, r: 4.5, fill: K[d.color || 'gray'] || K.gray, opacity: depth ? 0.6 : 1 })])
  return hs({ w: 'fill', h: 52, pad: [0, o.chevron === false ? 16 : 14, 0, 16 + depth * 22], gap: 10, fill: o.selected === d.name ? K.fill : null, name: 'Deck ' + d.name }, [
    lead,
    txt(d.name, { size: 17, weight: depth ? 'Regular' : 'Medium', w: 'fill' }),
    counts(d.n, d.l, d.r),
    o.chevron === false ? null : icon('chevron.right', 13, K.tertiary, 2.6),
  ])
}

function todayCard(w, o = {}) {
  return vs({ w: 'fill', pad: [18, 20, 20, 20], gap: 14, name: 'Today' }, [
    hs({ w: 'fill', justify: 'between' }, [txt('今日の学習', { size: 15, weight: 'SemiBold', color: K.secondary }), txt('約13分', { size: 15, color: K.secondary })]),
    hs({ gap: 6, align: 'end' }, [txt('98', { size: 48, weight: 'Bold', lh: 52 }), txt('枚', { size: 17, weight: 'Medium', color: K.secondary, lh: 30 })]),
    hs({ w: 'fill', gap: 24 }, [metric('35', null, '新規', K.blue, 22), metric('3', null, '学習中', K.red, 22), metric('60', null, '復習', K.green, 22)]),
    vs({ w: 'fill', gap: 6 }, [box({ dir: 'none', w: 'fill', h: 6, r: 3, fill: K.fill }, [rect((w - 72) * 0.32, 6, K.tint, 3)]), txt('今日は 46 枚学習しました', { size: 13, color: K.secondary })]),
    button('学習を始める', { icon: 'play' }),
  ])
}

// iPhone ─────────────────────────────────────────

const PW = 402
const PH = 874

function phoneDecks() {
  const s = screen('iPhone · デッキ', PW, PH)
  const content = vs({ w: PW, gap: 22, x: 0, y: 106 }, [
    largeTitle('デッキ', PW),
    hs({ w: PW, pad: [0, 16] }, [searchField(PW - 32, null, 'デッキを検索')]),
    section(PW, null, [todayCard(PW - 32)]),
    section(PW, 'すべてのデッキ', deckRows(), { inset: 48, headerAccessory: hs({ gap: 18 }, [txt('新規', { size: 12, color: K.blue, weight: 'Medium' }), txt('学習', { size: 12, color: K.red, weight: 'Medium' }), txt('復習', { size: 12, color: K.green, weight: 'Medium' }), gap(8)]) }),
  ])
  s.appendChild(content)
  place(s, statusBar(PW), 0, 0)
  place(s, glassCircle('sync'), 16, 58)
  place(s, glassGroup(['sort', 'plus']), PW - 16 - 88, 58)
  place(s, tabBar(PW, 0), 21, PH - 62 - 22)
  homeIndicator(s, PW, PH)
  return s
}

function phoneDeckOverview() {
  const s = screen('iPhone · デッキの概要', PW, PH)
  const content = vs({ w: PW, gap: 22, x: 0, y: 106 }, [
    vs({ w: PW, pad: [0, 16], gap: 2 }, [txt('学習 › 語学', { size: 15, weight: 'Medium', color: K.secondary }), txt('英単語 TOEIC', { size: 34, weight: 'Bold', lh: 41 }), txt('1,240枚・最終学習 今日 8:12', { size: 15, color: K.secondary })]),
    section(PW, null, [
      vs({ w: 'fill', pad: 20, gap: 18 }, [
        hs({ w: 'fill', justify: 'between' }, [metric('20', null, '新規', K.blue, 34), metric('3', null, '学習中', K.red, 34), metric('48', null, '復習', K.green, 34), gap(8)]),
        button('学習を始める', { icon: 'play' }),
        hs({ w: 'fill', gap: 10 }, [button('カスタム学習', { style: 'tinted', h: 44, size: 15 }), button('オプション', { style: 'tinted', h: 44, size: 15 })]),
      ]),
    ]),
    section(PW, '今後7日間', [vs({ w: 'fill', pad: [14, 20, 12, 20] }, [bars([71, 34, 52, 18, 40, 27, 61], { labels: ['今日', '水', '木', '金', '土', '日', '月'], h: 90 })])]),
    section(PW, '情報', [
      row('平均保持率（30日）', { detail: '91.4%' }),
      row('成熟カード', { detail: '612' }),
      row('未学習', { detail: '388' }),
      row('プリセット', { detail: 'Default・FSRS', chevron: true }),
    ]),
  ])
  s.appendChild(content)
  place(s, statusBar(PW), 0, 0)
  place(s, glassCircle('chevron.left'), 16, 58)
  place(s, glassGroup(['magnifyingglass', 'plus', 'ellipsis']), PW - 16 - 128, 58)
  place(s, tabBar(PW, 0), 21, PH - 62 - 22)
  homeIndicator(s, PW, PH)
  return s
}

function studyHeader(w, o = {}) {
  const pill = hs({ h: 44, r: 22, fill: K.glass, stroke: K.glassStroke, shadow: [2, 10, K.shadow * 0.6], pad: [0, 16], gap: 12, name: 'Counts' }, [
    hs({ gap: 3, align: 'end' }, [vs({ gap: 1, align: 'center' }, [txt('20', { size: 16, weight: 'Bold', color: K.blue }), rect(18, 2, o.answer ? '#00000000' : K.blue, 1)]), txt('新規', { size: 11, color: K.secondary })]),
    hs({ gap: 3, align: 'end' }, [vs({ gap: 1 }, [txt('3', { size: 16, weight: 'Bold', color: K.red }), rect(1, 2, '#00000000')]), txt('学習中', { size: 11, color: K.secondary })]),
    hs({ gap: 3, align: 'end' }, [vs({ gap: 1 }, [txt('48', { size: 16, weight: 'Bold', color: K.green }), rect(1, 2, '#00000000')]), txt('復習', { size: 11, color: K.secondary })]),
  ])
  const f = box({ dir: 'none', w, h: 44, name: 'Study Toolbar' })
  place(f, glassCircle('xmark'), 16, 0)
  place(f, pill, w / 2 - 105, 0)
  if (o.regular) place(f, glassGroup(['undo', 'flag', o.inspector ? 'sidebar.right' : 'info', 'ellipsis']), w - 16 - 168, 0)
  else place(f, glassCircle('ellipsis'), w - 60, 0)
  return f
}

function phoneStudy(answer) {
  const s = screen(answer ? 'iPhone · 学習（解答）' : 'iPhone · 学習（問題）', PW, PH, K.plain)
  place(s, cardContent(PW, answer, { top: 140 }), 0, 0)
  place(s, statusBar(PW), 0, 0)
  place(s, studyHeader(PW, { answer }), 0, 58)
  const bottom = answer
    ? vs({ w: PW, pad: [12, 16, 0, 16], gap: 8 }, [
        hs({ w: 'fill', gap: 8 }, [answerButton('again', '<1分', 82), gap(2), answerButton('hard', '6分', 82), answerButton('good', '10分', 82), answerButton('easy', '4日', 82)]),
      ])
    : vs({ w: PW, pad: [12, 16, 0, 16], gap: 10, align: 'center' }, [button('答えを表示', { h: 56 }), txt('カードをタップしても表示できます', { size: 13, color: K.secondary })])
  place(s, bottom, 0, PH - 34 - (answer ? 68 : 96))
  homeIndicator(s, PW, PH)
  return s
}

function phoneStudyLandscape() {
  const W = PH
  const H = PW
  const s = screen('iPhone 横 · 学習（解答）', W, H, K.plain)
  s.cornerRadius = 48
  place(s, cardContent(W - 120, true, { top: 70, big: 30 }), 60, 0)
  const tb = box({ dir: 'none', w: W, h: 44 })
  place(tb, glassCircle('xmark'), 62, 0)
  place(tb, hs({ h: 44, r: 22, fill: K.glass, stroke: K.glassStroke, pad: [0, 16], gap: 12 }, [txt('20', { size: 16, weight: 'Bold', color: K.blue }), txt('3', { size: 16, weight: 'Bold', color: K.red }), txt('48', { size: 16, weight: 'Bold', color: K.green })]), W / 2 - 60, 0)
  place(tb, glassGroup(['undo', 'ellipsis']), W - 62 - 88, 0)
  place(s, tb, 0, 12)
  place(s, hs({ w: W - 124, gap: 8, x: 62 }, [answerButton('again', '<1分', 160, 48), gap(4), answerButton('hard', '6分', 160, 48), answerButton('good', '10分', 160, 48), answerButton('easy', '4日', 160, 48)]), 62, H - 21 - 48)
  return s
}

function browseRow(front, sub, o = {}) {
  return hs({ w: 'fill', h: 62, pad: [0, 16, 0, 20], gap: 10, opacity: o.dim ? 0.45 : 1, fill: o.selected ? K.tint + '1F' : null }, [
    o.check != null ? box({ dir: 'h', w: 24, h: 24, r: 12, fill: o.check ? K.tint : null, stroke: o.check ? null : K.tertiary, sw: 1.5, justify: 'center' }, [o.check ? icon('checkmark', 13, '#FFFFFF', 3) : null]) : null,
    vs({ w: 'fill', gap: 2 }, [
      hs({ w: 'fill', gap: 6 }, [txt(front, { size: 17, w: 'fill' }), o.flag ? icon('flag.fill', 14, K[o.flag]) : null]),
      txt(sub, { size: 13, color: K.secondary, w: 'fill' }),
    ]),
    o.chevron === false ? null : icon('chevron.right', 13, K.tertiary, 2.6),
  ])
}
const CARDS = [
  ['ubiquitous', '英単語 TOEIC・今日・12日', { flag: 'red' }],
  ['meticulous', '英単語 TOEIC・明日・25日'],
  ['substantial', '英単語 TOEIC・3日後・1.2か月'],
  ['allocate', '英単語 TOEIC・今日・4日'],
  ['comply', '英単語 TOEIC・保留中・–', { dim: true }],
  ['tentative', '英単語 TOEIC・5日後・18日', { flag: 'green' }],
  ['endorse', '英単語 TOEIC・新規・–'],
  ['reimburse', '英単語 TOEIC・今日・2日'],
]

function phoneBrowse() {
  const s = screen('iPhone · ブラウズ', PW, PH)
  const content = vs({ w: PW, gap: 14, x: 0, y: 106 }, [
    largeTitle('ブラウズ', PW),
    hs({ w: PW, pad: [0, 16] }, [searchField(PW - 32, 'deck:"英単語 TOEIC" is:due')]),
    hs({ w: PW, pad: [0, 16], gap: 8 }, [chip('デッキ', '英単語 TOEIC', { active: true }), chip('状態', '期日', { active: true }), chip('タグ', null), chip('並び', '追加順')]),
    hs({ w: PW, pad: [0, 36] }, [txt('48枚', { size: 13, weight: 'Medium', color: K.secondary })]),
    section(PW, null, CARDS.slice(0, 8).map(([f, sub, o]) => browseRow(f, sub, o || {}))),
  ])
  s.appendChild(content)
  place(s, statusBar(PW), 0, 0)
  place(s, glassCircle('filter.circle'), 16, 58)
  place(s, glassGroup([box({ dir: 'h', h: 44, pad: [0, 10], align: 'center' }, [txt('選択', { size: 17, weight: 'Medium' })]), 'plus']), PW - 16 - 108, 58)
  place(s, tabBar(PW, 1), 21, PH - 62 - 22)
  homeIndicator(s, PW, PH)
  return s
}

function fieldBlock(name, value, focused, w) {
  return vs({ w: 'fill', pad: [12, 20, 14, 20], gap: 4 }, [
    txt(name, { size: 13, weight: 'SemiBold', color: focused ? K.tint : K.secondary }),
    txt(value, { size: 17, w: w - 72 }),
  ])
}

function phoneAddNote() {
  const s = screen('iPhone · カードを追加（シート）', PW, PH, '#000000')
  // underlying screen, scaled back like a sheet presentation
  place(s, box({ dir: 'none', w: PW - 32, h: 40, r: 14, fill: K === DARK ? '#2C2C2E' : '#D1D1D6' }), 16, 54)
  const sheet = box({ dir: 'none', w: PW, h: PH - 64, r: 38, fill: K.bg, clip: true, name: 'Sheet' })
  const form = vs({ w: PW, gap: 22, x: 0, y: 82 }, [
    section(PW, null, [row('ノートタイプ', { detail: 'Basic（裏表）', menu: true }), row('デッキ', { detail: '英単語 TOEIC', menu: true })]),
    section(PW, '表面', [fieldBlock('表面', 'ubiquitous', true, PW)], { header: null }),
    section(PW, '裏面', [fieldBlock('裏面', 'どこにでもある、遍在する\n/juːˈbɪkwɪtəs/', false, PW)]),
    section(PW, 'タグ', [hs({ w: 'fill', pad: [12, 20], gap: 8 }, [
      hs({ h: 30, r: 15, fill: K.tint + '1F', pad: [0, 10], gap: 5 }, [txt('TOEIC', { size: 13, weight: 'Medium', color: K.tint }), icon('xmark', 9, K.tint, 2.6)]),
      hs({ h: 30, r: 15, fill: K.tint + '1F', pad: [0, 10], gap: 5 }, [txt('頻出', { size: 13, weight: 'Medium', color: K.tint }), icon('xmark', 9, K.tint, 2.6)]),
      txt('タグを追加', { size: 15, color: K.tertiary }),
    ])]),
    section(PW, 'プレビュー', [vs({ w: 'fill', pad: 14, gap: 12, align: 'center' }, [segmented(160, ['表', '裏'], 0), txt('ubiquitous', { size: 28, weight: 'Bold', align: 'center', w: PW - 80 })])]),
  ])
  sheet.appendChild(form)
  const bar = box({ dir: 'none', w: PW, h: 60 })
  place(bar, glassCircle('xmark'), 16, 12)
  place(bar, txt('カードを追加', { size: 17, weight: 'SemiBold', w: 200, align: 'center' }), PW / 2 - 100, 22)
  place(bar, prominentCircle('checkmark'), PW - 60, 12)
  place(sheet, bar, 0, 4)
  // keyboard accessory (formatting) above the keyboard
  const acc = hs({ w: PW - 24, h: 48, r: 24, fill: K.glass, stroke: K.glassStroke, shadow: [2, 12, K.shadow], pad: [0, 8], justify: 'between', name: 'Formatting Bar (inputAccessoryView)' }, [
    ...['bold', 'italic', 'underline'].map((n) => box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon(n, 20)])),
    box({ dir: 'h', w: 64, h: 44, justify: 'center' }, [txt('[…]', { size: 15, weight: 'Bold', color: K.tint })]),
    box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('photo', 20)]),
    box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('textsize', 20)]),
    box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('chevron.down', 18, K.secondary)]),
  ])
  place(sheet, rect(PW, 300, K === DARK ? '#2C2C2E' : '#D1D3D9'), 0, PH - 64 - 300)
  place(sheet, txt('キーボード', { size: 15, color: K.secondary, w: PW, align: 'center' }), 0, PH - 64 - 160)
  place(sheet, acc, 12, PH - 64 - 300 - 58)
  place(s, sheet, 0, 64)
  place(s, statusBar(PW), 0, 0)
  return s
}

function phoneStats() {
  const s = screen('iPhone · 統計', PW, PH)
  const cw = PW - 32
  const content = vs({ w: PW, gap: 14, x: 0, y: 106 }, [
    largeTitle('統計', PW),
    hs({ w: PW, pad: [0, 16] }, [segmented(cw, ['1か月', '3か月', '1年', '全期間'], 1)]),
    vs({ w: PW, pad: [0, 16], gap: 14 }, [
      statCard(cw, '今日', [hs({ w: 'fill', justify: 'between' }, [metric('46', '枚', '学習'), metric('9', '分', '時間'), metric('89', '%', '正答率'), gap(10)])]),
      statCard(cw, '学習カレンダー', [heatmap(23, 11)], { badge: '連続 12日' }),
      statCard(cw, '回答ボタン', [
        hs({ w: 'fill', h: 10, r: 5, clip: true, gap: 2 }, [rect(cw * 0.1, 10, K.red), rect(cw * 0.12, 10, K.orange), rect(cw * 0.6, 10, K.green), rect(cw * 0.1, 10, K.blue)]),
        hs({ w: 'fill', justify: 'between' }, [['もう一度 11%', K.red], ['難しい 13%', K.orange], ['普通 64%', K.green], ['簡単 12%', K.blue]].map(([l, c]) => hs({ gap: 4 }, [box({ dir: 'none', w: 8, h: 8, r: 4, fill: c }), txt(l, { size: 12, color: K.secondary })]))),
      ]),
    ]),
  ])
  s.appendChild(content)
  place(s, statusBar(PW), 0, 0)
  place(s, glassGroup([box({ dir: 'h', h: 44, pad: [0, 12], gap: 6, align: 'center' }, [txt('すべてのデッキ', { size: 15, weight: 'SemiBold' }), icon('chevron.down', 12, K.label, 2.6)])]), 16, 58)
  place(s, glassGroup(['share', 'info']), PW - 16 - 88, 58)
  place(s, tabBar(PW, 2), 21, PH - 62 - 22)
  homeIndicator(s, PW, PH)
  return s
}

function phoneSettings() {
  const s = screen('iPhone · 設定', PW, PH)
  const content = vs({ w: PW, gap: 22, x: 0, y: 106 }, [
    largeTitle('設定', PW),
    section(PW, null, [row('同期', { iconSquare: ['icloud', K.blue], subtitle: 'iCloud・同期済み 2分前', chevron: true })]),
    section(PW, '学習', [
      row('1日の新規カード', { iconSquare: ['star', K.blue], detail: '20', menu: true }),
      row('1日の最大復習数', { iconSquare: ['undo', K.green], detail: '200', menu: true }),
      row('目標保持率', { iconSquare: ['chart', K.purple], detail: '90%', menu: true }),
      row('FSRS', { iconSquare: ['wand', K.orange], toggle: true }),
    ], { footer: '「Default」プリセットの値です。デッキごとの設定はデッキのオプションで変更できます。' }),
    section(PW, '学習画面', [
      row('回答ボタン', { iconSquare: ['hand', K.red], detail: '4ボタン', menu: true }),
      row('ボタンに次回間隔を表示', { iconSquare: ['calendar', K.teal], toggle: true }),
      row('音声を自動再生', { iconSquare: ['speaker', K.gray], toggle: true }),
    ]),
  ])
  s.appendChild(content)
  place(s, statusBar(PW), 0, 0)
  place(s, tabBar(PW, 3), 21, PH - 62 - 22)
  homeIndicator(s, PW, PH)
  return s
}

// iPad ─────────────────────────────────────────

const DW = 1210
const DH = 834

function sidebar(h, sel, o = {}) {
  const item = (ic, label, badge, key) => {
    const on = sel === key
    return hs({ w: 'fill', h: 44, r: 14, fill: on ? K.tint : null, pad: [0, 12], gap: 12 }, [
      icon(ic, 21, on ? '#FFFFFF' : K.tint),
      txt(label, { size: 17, weight: on ? 'SemiBold' : 'Regular', color: on ? '#FFFFFF' : K.label, w: 'fill' }),
      badge ? txt(badge, { size: 15, color: on ? '#FFFFFFCC' : K.secondary }) : null,
    ])
  }
  const deck = (d, depth) => {
    const on = sel === d.name
    return hs({ w: 'fill', h: 40, r: 12, fill: on ? K.tint : null, pad: [0, 12, 0, 12 + depth * 20], gap: 10 }, [
      d.kids ? icon('chevron.down', 12, on ? '#FFFFFF' : K.secondary, 2.6) : box({ dir: 'h', w: 12, h: 12, justify: 'center' }, [box({ dir: 'none', w: 8, h: 8, r: 4, fill: on ? '#FFFFFF' : K[d.color || 'gray'] || K.gray })]),
      txt(d.name, { size: 16, weight: on ? 'SemiBold' : 'Regular', color: on ? '#FFFFFF' : K.label, w: 'fill' }),
      txt(String(d.n + d.l + d.r || ''), { size: 15, color: on ? '#FFFFFFCC' : K.secondary }),
    ])
  }
  const deckItems = []
  for (const d of DECKS) {
    deckItems.push(deck(d, 0))
    if (d.kids) for (const k of d.kids) deckItems.push(deck(k, 1))
  }
  const head = (s) => hs({ w: 'fill', h: 34, pad: [0, 12], justify: 'between', align: 'end' }, [txt(s, { size: 15, weight: 'Bold' }), icon('chevron.down', 12, K.secondary, 2.6)])
  const f = vs({ w: 320, h: h - 16, r: 28, fill: K.glass, stroke: K.glassStroke, shadow: [4, 30, K.shadow], pad: [12, 12, 12, 12], gap: 4, clip: true, name: 'Sidebar (floating glass)' }, [
    hs({ w: 'fill', h: 44, justify: 'between' }, [box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('sidebar', 22)]), hs({ gap: 4 }, [box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('sync', 21)]), box({ dir: 'h', w: 44, h: 44, justify: 'center' }, [icon('plus', 22)])])]),
    hs({ w: 'fill', pad: [4, 4, 8, 4] }, [txt('Negoto', { size: 28, weight: 'Bold', lh: 34 })]),
    searchField(296, null, '検索'),
    gap(6),
    item('calendar', '今日の学習', '98', 'today'),
    item('list', 'ブラウズ', '1,972', 'browse'),
    item('chart', '統計', null, 'stats'),
    item('gear', '設定', null, 'settings'),
    gap(6),
    head('デッキ'),
    ...deckItems,
    gap(6),
    head('タグ'),
    ...['TOEIC', '頻出', 'leech'].map((t) => hs({ w: 'fill', h: 40, pad: [0, 12], gap: 10 }, [icon('tag', 18, K.secondary), txt(t, { size: 16, w: 'fill' })])),
  ])
  return f
}

function padDeckOverview() {
  const s = screen('iPad 横 · デッキの概要（サイドバー）', DW, DH)
  const x0 = 336
  const cw = DW - x0
  const colW = (cw - 48 - 20) / 2
  const content = vs({ w: cw, gap: 22, pad: [0, 24], x: x0, y: 72 }, [
    vs({ w: 'fill', gap: 2 }, [txt('学習 › 語学', { size: 15, weight: 'Medium', color: K.secondary }), txt('英単語 TOEIC', { size: 34, weight: 'Bold', lh: 41 }), txt('1,240枚・サブデッキなし・最終学習 今日 8:12', { size: 15, color: K.secondary })]),
    hs({ w: 'fill', gap: 20, align: 'start' }, [
      vs({ w: colW, gap: 20 }, [
        vs({ w: 'fill', r: 26, fill: K.cell, pad: 22, gap: 20 }, [
          hs({ w: 'fill', justify: 'between' }, [metric('20', null, '新規', K.blue, 40), metric('3', null, '学習中', K.red, 40), metric('48', null, '復習', K.green, 40), gap(20)]),
          button('学習を始める', { icon: 'play' }),
          hs({ w: 'fill', gap: 10 }, [button('カスタム学習', { style: 'tinted', h: 44, size: 15 }), button('オプション', { style: 'tinted', h: 44, size: 15 })]),
        ]),
        vs({ w: 'fill', r: 26, fill: K.cell, clip: true }, [row('平均保持率（30日）', { detail: '91.4%' }), hs({ w: 'fill', pad: [0, 0, 0, 20] }, [line('fill')]), row('成熟カード', { detail: '612' }), hs({ w: 'fill', pad: [0, 0, 0, 20] }, [line('fill')]), row('未学習', { detail: '388' }), hs({ w: 'fill', pad: [0, 0, 0, 20] }, [line('fill')]), row('保留中', { detail: '14' })]),
      ]),
      vs({ w: colW, gap: 20 }, [
        statCard(colW, '今後7日間', [bars([71, 34, 52, 18, 40, 27, 61], { labels: ['今日', '水', '木', '金', '土', '日', '月'], h: 120, bw: 30 })]),
        statCard(colW, '説明', [txt('TOEIC 頻出の英単語 1,240 語。例文と発音つき。\n毎日 20 語ずつ新しい単語を学習します。', { size: 15, color: K.secondary, w: colW - 36, lh: 22 })]),
        vs({ w: 'fill', r: 26, fill: K.cell, clip: true }, [row('プリセット', { detail: 'Default', chevron: true }), hs({ w: 'fill', pad: [0, 0, 0, 20] }, [line('fill')]), row('1日の上限', { detail: '新規 20・復習 200' }), hs({ w: 'fill', pad: [0, 0, 0, 20] }, [line('fill')]), row('スケジューラ', { detail: 'FSRS' })]),
      ]),
    ]),
  ])
  s.appendChild(content)
  place(s, sidebar(DH, '英単語 TOEIC'), 8, 8)
  place(s, statusBar(DW, true), 0, 0)
  place(s, glassGroup(['magnifyingglass', 'plus', 'ellipsis']), DW - 24 - 128, 20)
  homeIndicator(s, DW, DH)
  return s
}

function padToday() {
  // iPad portrait: sidebar collapsed, "Today" list in the detail column
  const W = 834
  const H = 1210
  const s = screen('iPad 縦 · 今日の学習（サイドバーを隠した状態）', W, H)
  const content = vs({ w: W, gap: 22, x: 0, y: 84 }, [
    hs({ w: W, pad: [0, 24] }, [txt('今日の学習', { size: 34, weight: 'Bold', lh: 41 })]),
    hs({ w: W, pad: [0, 8] }, [section(W - 16, null, [todayCard(W - 48)])]),
    hs({ w: W, pad: [0, 8] }, [section(W - 16, 'すべてのデッキ', deckRows(), { inset: 48 })]),
  ])
  s.appendChild(content)
  place(s, statusBar(W, true), 0, 0)
  place(s, glassCircle('sidebar'), 24, 24)
  place(s, glassGroup(['sort', 'sync', 'plus']), W - 24 - 128, 24)
  homeIndicator(s, W, H)
  return s
}

function padBrowse() {
  const s = screen('iPad 横 · ブラウズ（表 + インスペクタ）', DW, DH)
  const x0 = 336
  const inspW = 360
  const tw = DW - x0 - inspW
  const header = hs({ w: tw, h: 36, pad: [0, 20], gap: 0 }, [
    txt('表面', { size: 13, weight: 'SemiBold', color: K.secondary, w: 'fill' }),
    txt('デッキ', { size: 13, weight: 'SemiBold', color: K.secondary, w: 120 }),
    txt('期日', { size: 13, weight: 'SemiBold', color: K.secondary, w: 70 }),
    txt('間隔', { size: 13, weight: 'SemiBold', color: K.secondary, w: 70 }),
  ])
  const rows = CARDS.map(([f, sub, o], i) => {
    const [deck, due, ivl] = sub.split('・')
    const sel = i === 0
    return hs({ w: tw - 16, h: 44, r: 10, pad: [0, 12], fill: sel ? K.tint : null, opacity: o && o.dim ? 0.45 : 1 }, [
      hs({ w: 'fill', gap: 6 }, [txt(f, { size: 15, weight: sel ? 'SemiBold' : 'Regular', color: sel ? '#FFFFFF' : K.label }), o && o.flag ? icon('flag.fill', 13, sel ? '#FFFFFF' : K[o.flag]) : null, spacer()]),
      txt(deck, { size: 15, color: sel ? '#FFFFFFDD' : K.secondary, w: 120 }),
      txt(due, { size: 15, color: sel ? '#FFFFFFDD' : K.secondary, w: 70 }),
      txt(ivl, { size: 15, color: sel ? '#FFFFFFDD' : K.secondary, w: 70 }),
    ])
  })
  const table = vs({ w: tw, gap: 10, x: x0, y: 76 }, [
    hs({ w: tw, pad: [0, 20] }, [txt('ブラウズ', { size: 34, weight: 'Bold', lh: 41 })]),
    hs({ w: tw, pad: [0, 20] }, [searchField(tw - 40, 'deck:"英単語 TOEIC" is:due')]),
    hs({ w: tw, pad: [0, 20], gap: 8 }, [chip('デッキ', '英単語 TOEIC', { active: true }), chip('状態', '期日', { active: true }), chip('タグ', null), chip('並び', '追加順'), spacer(), txt('48枚', { size: 13, weight: 'Medium', color: K.secondary })]),
    header,
    line(tw),
    vs({ w: tw, pad: [4, 8], gap: 0 }, rows),
  ])
  s.appendChild(table)
  // inspector
  const insp = vs({ w: inspW, h: DH, fill: K.bg, pad: [76, 0, 0, 0], gap: 18, x: DW - inspW, y: 0, name: 'Inspector (note editor)' }, [
    hs({ w: 'fill', pad: [0, 20], justify: 'between' }, [txt('ノートを編集', { size: 22, weight: 'Bold' }), hs({ gap: 4 }, [icon('checkmark', 14, K.green, 2.6), txt('自動保存済み', { size: 13, weight: 'Medium', color: K.green })])]),
    section(inspW, null, [row('ノートタイプ', { detail: 'Basic' }), row('デッキ', { detail: '英単語 TOEIC', menu: true })]),
    section(inspW, '表面', [fieldBlock('表面', 'ubiquitous', true, inspW)]),
    section(inspW, '裏面', [fieldBlock('裏面', 'どこにでもある、遍在する\n/juːˈbɪkwɪtəs/', false, inspW)]),
    section(inspW, 'プレビュー', [vs({ w: 'fill', pad: 14, gap: 12, align: 'center' }, [segmented(150, ['表', '裏'], 1), txt('どこにでもある', { size: 20, weight: 'Bold', align: 'center', w: inspW - 80 })])]),
  ])
  place(s, line(0.5, K.separator, DH), DW - inspW, 0)
  s.appendChild(insp)
  place(s, sidebar(DH, 'browse'), 8, 8)
  place(s, statusBar(DW, true), 0, 0)
  place(s, glassGroup(['filter', box({ dir: 'h', h: 44, pad: [0, 10], align: 'center' }, [txt('選択', { size: 17, weight: 'Medium' })]), 'plus']), DW - inspW - 24 - 150, 20)
  place(s, glassGroup(['trash', 'sidebar.right']), DW - 24 - 88, 20)
  homeIndicator(s, DW, DH)
  return s
}

function padStudy() {
  const s = screen('iPad 横 · 学習（インスペクタ表示）', DW, DH, K.plain)
  const inspW = 340
  const cw = DW - inspW
  place(s, cardContent(cw, true, { top: 150, big: 44 }), 0, 0)
  place(s, statusBar(DW, true), 0, 0)
  place(s, studyHeader(cw, { answer: true, regular: true, inspector: true }), 0, 24)
  const bw = 150
  place(s, vs({ w: cw, align: 'center', gap: 8 }, [
    hs({ gap: 10 }, [answerButton('again', '<1分', bw, 60), gap(6), answerButton('hard', '6分', bw, 60), answerButton('good', '10分', bw, 60), answerButton('easy', '4日', bw, 60)]),
    hs({ gap: 10 }, ['1', '2', '3', '4'].map((k, i) => box({ dir: 'h', w: bw + (i === 0 ? 16 : 0), justify: 'center' }, [box({ dir: 'h', w: 20, h: 20, r: 5, stroke: K.tertiary, justify: 'center' }, [txt(k, { size: 11, weight: 'SemiBold', color: K.secondary })])]))),
  ]), 0, DH - 40 - 92)
  const info = (t, v) => row(t, { detail: v, h: 46 })
  const insp = vs({ w: inspW, h: DH, fill: K.bg, pad: [76, 0, 0, 0], gap: 18, x: cw, y: 0, name: 'Inspector (card info)' }, [
    hs({ w: 'fill', pad: [0, 20] }, [txt('カード情報', { size: 22, weight: 'Bold' })]),
    section(inspW, null, [info('次回（普通）', '10分'), info('追加日', '2026/9/12'), info('復習回数', '4回'), info('ラプス', '1回'), info('安定度', '3.2日'), info('難易度', '6.1 / 10')]),
    section(inspW, '履歴', [
      ...[['10/05', '普通・間隔 3日', K.green], ['10/02', 'もう一度', K.red], ['09/28', '普通・間隔 4日', K.green]].map(([d, t, c]) => hs({ w: 'fill', h: 40, pad: [0, 20], gap: 10 }, [box({ dir: 'none', w: 8, h: 8, r: 4, fill: c }), txt(d, { size: 15, color: K.secondary }), txt(t, { size: 15 })])),
    ]),
    section(inspW, 'タグ', [hs({ w: 'fill', pad: [12, 20], gap: 8 }, ['TOEIC', '頻出'].map((t) => hs({ h: 28, r: 14, fill: K.tint + '1F', pad: [0, 10] }, [txt(t, { size: 13, weight: 'Medium', color: K.tint })])))]),
    hs({ w: 'fill', pad: [0, 16] }, [button('ノートを編集', { style: 'tinted', icon: 'pencil', h: 44, size: 15 })]),
  ])
  place(s, line(0.5, K.separator, DH), cw, 0)
  s.appendChild(insp)
  homeIndicator(s, DW, DH)
  return s
}

function padStats() {
  const s = screen('iPad 横 · 統計（カードのグリッド）', DW, DH)
  const x0 = 336
  const cw = DW - x0 - 48
  const c3 = (cw - 28) / 3
  const content = vs({ w: DW - x0, gap: 18, pad: [0, 24], x: x0, y: 76 }, [
    hs({ w: 'fill', justify: 'between', align: 'end' }, [txt('統計', { size: 34, weight: 'Bold', lh: 41 }), segmented(360, ['1か月', '3か月', '1年', '全期間'], 1)]),
    hs({ w: 'fill', gap: 14, align: 'start' }, [
      statCard(c3, '今日', [hs({ w: 'fill', justify: 'between' }, [metric('46', '枚', '学習'), metric('9', '分', '時間'), metric('89', '%', '正答率')])]),
      statCard(c3, '保持率', [hs({ w: 'fill', justify: 'between', align: 'end' }, [metric('91.4', '%', '目標 90%'), hs({ gap: 4, align: 'end' }, [62, 70, 58, 74, 80, 77, 85, 88].map((v, i) => rect(10, v * 0.6, v > 72 ? K.tint : K.tint + '55', 3)))])]),
      statCard(c3, '回答ボタン', [
        hs({ w: 'fill', h: 10, r: 5, clip: true, gap: 2 }, [rect(c3 * 0.1, 10, K.red), rect(c3 * 0.12, 10, K.orange), rect(c3 * 0.55, 10, K.green), rect(c3 * 0.09, 10, K.blue)]),
        hs({ w: 'fill', gap: 10 }, [['11%', K.red], ['13%', K.orange], ['64%', K.green], ['12%', K.blue]].map(([l, c]) => hs({ gap: 4 }, [box({ dir: 'none', w: 8, h: 8, r: 4, fill: c }), txt(l, { size: 12, color: K.secondary })]))),
      ]),
    ]),
    hs({ w: 'fill', gap: 14, align: 'start' }, [
      statCard(c3 * 2 + 14, '学習カレンダー', [heatmap(36, 12)], { badge: '連続 12日' }),
      statCard(c3, '今後7日間', [bars([71, 34, 52, 18, 40, 27, 61], { labels: ['今日', '水', '木', '金', '土', '日', '月'], h: 70, bw: 18 })]),
    ]),
    hs({ w: 'fill', gap: 14, align: 'start' }, [
      statCard(c3 * 2 + 14, '復習間隔の分布', [hs({ w: 'fill', h: 110, gap: 3, align: 'end' }, [40, 62, 80, 75, 66, 58, 50, 44, 40, 35, 30, 27, 24, 20, 18, 15, 13, 11, 9, 8, 7, 6, 5, 4].map((v) => rect(17, v * 1.3, K.blue + 'CC', 3)))]),
      statCard(c3, 'カードの状態', [
        ...[['成熟', '612', K.tint], ['若い', '240', K.tint + '77'], ['学習中', '18', K.red], ['未学習', '388', K.blue], ['保留中', '14', K.gray]].map(([l, v, c]) => hs({ w: 'fill', gap: 8 }, [box({ dir: 'none', w: 8, h: 8, r: 4, fill: c }), txt(l, { size: 15, w: 'fill' }), txt(v, { size: 15, weight: 'SemiBold' })])),
      ]),
    ]),
  ])
  s.appendChild(content)
  place(s, sidebar(DH, 'stats'), 8, 8)
  place(s, statusBar(DW, true), 0, 0)
  place(s, glassGroup([box({ dir: 'h', h: 44, pad: [0, 12], gap: 6, align: 'center' }, [txt('すべてのデッキ', { size: 15, weight: 'SemiBold' }), icon('chevron.down', 12, K.label, 2.6)]), 'share', 'info']), DW - 24 - 250, 20)
  homeIndicator(s, DW, DH)
  return s
}

// Foundations ─────────────────────────────────────

function foundations() {
  const W = 1210
  const f = vs({ w: W, fill: K.bg, pad: 40, gap: 28, r: 18, name: 'Foundations' }, [
    txt('Negoto — デザインの基礎（HIG 準拠）', { size: 34, weight: 'Bold', lh: 41 }),
    txt('システムカラーとマテリアル、Dynamic Type、44pt 以上のタップ領域。Liquid Glass はナビゲーションと操作の層だけに使い、カードやリストなどのコンテンツは不透明な面に置きます。', { size: 17, color: K.secondary, w: W - 80, lh: 26 }),
    txt('カラー（ライト / ダーク）', { size: 22, weight: 'Bold' }),
    hs({ gap: 14 }, [
      ['Accent / New', LIGHT.blue, DARK.blue, 'systemBlue'],
      ['Learning / Again', LIGHT.red, DARK.red, 'systemRed'],
      ['Hard', LIGHT.orange, DARK.orange, 'systemOrange'],
      ['Review / Good', LIGHT.green, DARK.green, 'systemGreen'],
      ['Easy', LIGHT.blue, DARK.blue, 'systemBlue'],
      ['Background', LIGHT.bg, DARK.bg, 'systemGroupedBackground'],
      ['Content', LIGHT.cell, DARK.cell, 'secondarySystemGroupedBackground'],
    ].map(([n, l, d, sys]) => vs({ w: 150, gap: 6 }, [
      hs({ gap: 0, r: 16, clip: true, stroke: K.separator }, [rect(75, 64, l), rect(75, 64, d)]),
      txt(n, { size: 15, weight: 'SemiBold' }),
      txt(sys, { size: 12, color: K.secondary, w: 150 }),
    ]))),
    txt('文字（Dynamic Type）', { size: 22, weight: 'Bold' }),
    hs({ gap: 40, align: 'start' }, [
      vs({ gap: 10 }, [
        ['Large Title 34 Bold', 34, 'Bold'], ['Title 2 22 Bold', 22, 'Bold'], ['Headline 17 Semibold', 17, 'SemiBold'], ['Body 17 Regular', 17, 'Regular'], ['Subheadline 15', 15, 'Regular'], ['Footnote 13', 13, 'Regular'], ['Caption 12', 12, 'Regular'],
      ].map(([t, s, w]) => txt(t, { size: s, weight: w }))),
      vs({ gap: 16, w: 420 }, [
        txt('部品', { size: 17, weight: 'SemiBold' }),
        button('学習を始める', { icon: 'play', w: 380 }),
        hs({ gap: 10 }, [button('カスタム学習', { style: 'tinted', h: 44, size: 15, w: 185 }), button('オプション', { style: 'tinted', h: 44, size: 15, w: 185 })]),
        hs({ gap: 8 }, [answerButton('again', '<1分', 88), answerButton('hard', '6分', 88), answerButton('good', '10分', 88), answerButton('easy', '4日', 88)]),
        hs({ gap: 10 }, [glassCircle('xmark'), glassGroup(['undo', 'flag', 'info', 'ellipsis']), prominentCircle('checkmark')]),
        hs({ gap: 8 }, [chip('デッキ', '英単語', { active: true }), chip('状態', 'すべて'), counts(20, 3, 48)]),
        segmented(300, ['1か月', '3か月', '1年', '全期間'], 1),
      ]),
      vs({ gap: 12, w: 300 }, [
        txt('レイアウト', { size: 17, weight: 'SemiBold' }),
        txt('• 横幅が compact: 下のタブバー（デッキ・ブラウズ・統計・設定）+ NavigationStack\n• 横幅が regular: NavigationSplitView（フローティングのサイドバー + 詳細）\n• ブラウズ（regular）: 表 + インスペクタで編集\n• 学習: 全画面。iPad はインスペクタにカード情報\n• フォームは Form / insetGrouped、読みやすい最大幅で中央寄せ', { size: 15, color: K.secondary, w: 300, lh: 23 }),
      ]),
    ]),
  ])
  return f
}

// ───────────────────────── Assemble ─────────────────────────

const old = figma.root.children.slice()
function pageWith(name, frames, cols) {
  const p = figma.createPage()
  p.name = name
  figma.currentPage = p
  let x = 0
  let y = 0
  let rowH = 0
  frames.forEach((fn, i) => {
    const f = fn()
    p.appendChild(f)
    if (i > 0 && i % cols === 0) {
      x = 0
      y += rowH + 140
      rowH = 0
    }
    const label = txt(f.name, { size: 28, weight: 'Bold', color: '#8E8E93' })
    p.appendChild(label)
    label.x = x
    label.y = y
    f.x = x
    f.y = y + 56
    x += f.width + 100
    rowH = Math.max(rowH, f.height + 56)
  })
  return p
}

pageWith('Foundations', [foundations], 1)
pageWith('iPhone', [phoneDecks, phoneDeckOverview, () => phoneStudy(false), () => phoneStudy(true), phoneBrowse, phoneAddNote, phoneStats, phoneSettings, phoneStudyLandscape], 4)
pageWith('iPad', [padDeckOverview, padBrowse, padStudy, padStats, padToday], 2)
K = DARK
pageWith('Dark', [phoneDecks, () => phoneStudy(true), padDeckOverview], 3)
K = LIGHT
for (const p of old) p.remove()
return figma.root.children.map((p) => `${p.name}: ${p.children.length}`)
