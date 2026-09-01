import { useEffect, useState, useRef } from 'react'
import {
  collection, doc, onSnapshot, setDoc, updateDoc,
  arrayUnion, serverTimestamp, query
} from 'firebase/firestore'
import { db } from '../firebase'
import { CATALOG, allCatalogDishes } from '../catalog'

// U+001F unit separator — same as Flutter catalogDishStorageKey separator
const SEP = ''
const CUSTOM_PREFIX = '__custom__'
const SEC_PREFIX = '__section__'

function keyToDocId(key) {
  const bytes = new TextEncoder().encode(key)
  let bin = ''
  bytes.forEach(b => (bin += String.fromCharCode(b)))
  return btoa(bin).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function sectionKey(sectionId) { return `${SEC_PREFIX}${SEP}${sectionId}` }

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(r.result.split(',')[1])
    r.onerror = reject
    r.readAsDataURL(file)
  })
}

const MENU_DOC    = doc(db, 'admin_public', 'menu_overrides')
const snapsColl   = collection(db, 'admin_public', 'menu_overrides', 'snapshots')
const secSnapColl = collection(db, 'admin_public', 'menu_overrides', 'section_snapshots')

const emptyDish = { title: '', subtitle: '', price: '', badge: '' }

function imgSrc(b64) {
  if (!b64) return null
  if (b64.startsWith('data:')) return b64
  return `data:image/jpeg;base64,${b64}`
}

export default function Menu() {
  const [meta, setMeta]         = useState({ deletedDishKeys: [], deletedSectionIds: [], customCategoryIds: [] })
  const [snaps, setSnaps]       = useState({})
  const [secSnaps, setSecSnaps] = useState({})
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [tab, setTab]           = useState('All')
  const [busy, setBusy]         = useState(null)

  const [editDish, setEditDish]       = useState(null)
  const [dishForm, setDishForm]       = useState({})
  const [dishImgPrev, setDishImgPrev] = useState(null)
  const [dishImgB64, setDishImgB64]   = useState(null)
  const dishImgRef = useRef()

  const [editCat, setEditCat]           = useState(null)
  const [catForm, setCatForm]           = useState({ title: '', subtitle: '' })
  const [catImgPrev, setCatImgPrev]     = useState(null)
  const [catImgB64, setCatImgB64]       = useState(null)
  const [catRemoveImg, setCatRemoveImg] = useState(false)
  const catImgRef = useRef()

  const [addCatOpen, setAddCatOpen] = useState(false)
  const [newCatName, setNewCatName] = useState('')

  const [addDishSec, setAddDishSec]         = useState(null)
  const [newDish, setNewDish]               = useState(emptyDish)
  const [newDishImgB64, setNewDishImgB64]   = useState(null)
  const [newDishImgPrev, setNewDishImgPrev] = useState(null)
  const newDishImgRef = useRef()

  useEffect(() => {
    let n = 0
    const done = () => { if (++n >= 3) setLoading(false) }
    const u1 = onSnapshot(MENU_DOC, s => {
      const d = s.data() || {}
      setMeta({ deletedDishKeys: d.deletedDishKeys || [], deletedSectionIds: d.deletedSectionIds || [], customCategoryIds: d.customCategoryIds || [] })
      done()
    })
    const u2 = onSnapshot(query(snapsColl), s => {
      const m = {}
      s.docs.forEach(d => { const { key, data } = d.data(); if (key) m[key] = { ...data, _docId: d.id } })
      setSnaps(m); done()
    })
    const u3 = onSnapshot(query(secSnapColl), s => {
      const m = {}
      s.docs.forEach(d => { const { key, data } = d.data(); if (key) m[key] = { ...data, _docId: d.id } })
      setSecSnaps(m); done()
    })
    return () => { u1(); u2(); u3() }
  }, [])

  const deletedSet  = new Set(meta.deletedDishKeys)
  const deletedSecs = new Set(meta.deletedSectionIds)

  const catalogDishes = allCatalogDishes()
    .filter(d => !deletedSecs.has(d.section) && !deletedSet.has(d.key))
    .map(d => {
      const ov = snaps[d.key] || {}
      return { ...d,
        title:       ov.title     || d.title,
        subtitle:    ov.subtitle  || d.subtitle,
        price:       ov.price     || d.price,
        badge:       ov.badge     !== undefined ? ov.badge : d.badge,
        available:   ov.available !== undefined ? ov.available : true,
        imageBase64: ov.imageBase64 || null,
        isCustom:    false,
      }
    })

  const customDishes = []
  meta.customCategoryIds.forEach(catId => {
    if (deletedSecs.has(catId)) return
    const prefix = `${CUSTOM_PREFIX}${catId}${SEP}`
    Object.entries(snaps).forEach(([k, data]) => {
      if (!k.startsWith(prefix) || deletedSet.has(k)) return
      customDishes.push({ key: k, section: catId, title: data.title || '', subtitle: data.subtitle || '',
        price: data.price || '', badge: data.badge || null,
        available: data.available !== undefined ? data.available : true,
        imageBase64: data.imageBase64 || null, isCustom: true })
    })
  })

  const allDishes  = [...catalogDishes, ...customDishes]
  const availCount = allDishes.filter(d => d.available).length

  const catalogTabs = CATALOG.map(s => s.section).filter(s => !deletedSecs.has(s))
  const customTabs  = meta.customCategoryIds.filter(c => !deletedSecs.has(c))
  const allTabs     = ['All', ...catalogTabs, ...customTabs]

  const filtered = allDishes.filter(d => {
    const okTab = tab === 'All' || d.section === tab
    const okQ   = !search || d.title.toLowerCase().includes(search.toLowerCase()) || d.subtitle.toLowerCase().includes(search.toLowerCase())
    return okTab && okQ
  })

  const isCustomTab = customTabs.includes(tab)

  function getCatSnap(sectionId)     { return secSnaps[sectionKey(sectionId)] || null }
  function getCatTitle(sectionId)    { return getCatSnap(sectionId)?.title || sectionId }
  function getCatSubtitle(sectionId) {
    const snap    = getCatSnap(sectionId)
    const catalog = CATALOG.find(s => s.section === sectionId)
    return snap?.subtitle || catalog?.subtitle || ''
  }
  // Fallback to the same local asset images the Flutter app uses
  const CATALOG_FALLBACK_IMAGES = {
    'Puttu':               '/menus/puttu.png',
    'Gravies & Curries':   '/menus/gravies.png',
    'Desserts':            '/menus/desserts.png',
    'Our Signature Dishes':'/menus/signature.png',
  }

  function getCatImage(sectionId) {
    const b64 = getCatSnap(sectionId)?.imageBase64
    if (b64) return `data:image/jpeg;base64,${b64}`
    return CATALOG_FALLBACK_IMAGES[sectionId] || null
  }

  async function saveDishSnap(key, data) {
    const docId = keyToDocId(key)
    await setDoc(doc(snapsColl, docId), { key, data, updated_at: serverTimestamp() }, { merge: true })
  }
  async function saveSecSnap(sectionId, data) {
    const key = sectionKey(sectionId)
    await setDoc(doc(secSnapColl, keyToDocId(key)), { key, data, updated_at: serverTimestamp() }, { merge: true })
  }

  async function toggleAvail(dish) {
    setBusy(dish.key)
    try {
      const ov = snaps[dish.key] || {}
      await saveDishSnap(dish.key, { ...ov, title: dish.title, subtitle: dish.subtitle,
        price: dish.price, badge: dish.badge || null, available: !dish.available,
        imageBase64: dish.imageBase64 || null })
    } finally { setBusy(null) }
  }

  async function deleteDish(dish) {
    if (!confirm(`Hide "${dish.title}" from the menu?\nCustomers will not see it.`)) return
    setBusy(dish.key)
    try { await updateDoc(MENU_DOC, { deletedDishKeys: arrayUnion(dish.key), deletedDishKeysUpdatedAt: serverTimestamp() }) }
    finally { setBusy(null) }
  }

  async function deleteSection(sectionId) {
    if (!confirm(`Delete "${sectionId}" and all its dishes?`)) return
    await updateDoc(MENU_DOC, { deletedSectionIds: arrayUnion(sectionId) })
    setTab('All')
  }

  function openEditDish(dish) {
    setEditDish(dish)
    setDishForm({ title: dish.title, subtitle: dish.subtitle, price: dish.price, badge: dish.badge || '', available: dish.available })
    setDishImgPrev(imgSrc(dish.imageBase64))
    setDishImgB64(null)
  }
  async function onDishImgChange(e) {
    const f = e.target.files?.[0]; if (!f) return
    const b64 = await fileToBase64(f); setDishImgB64(b64); setDishImgPrev(imgSrc(b64))
  }
  async function handleEditDishSave(e) {
    e.preventDefault(); if (!editDish) return
    setBusy(editDish.key)
    try {
      const ov = snaps[editDish.key] || {}
      await saveDishSnap(editDish.key, { ...ov,
        title: dishForm.title.trim(), subtitle: dishForm.subtitle.trim(),
        price: dishForm.price.trim(), badge: dishForm.badge.trim() || null,
        available: dishForm.available, imageBase64: dishImgB64 || ov.imageBase64 || null })
      setEditDish(null)
    } finally { setBusy(null) }
  }

  function openEditCat(sectionId) {
    setEditCat(sectionId)
    const snap    = getCatSnap(sectionId)
    const catalog = CATALOG.find(s => s.section === sectionId)
    setCatForm({ title: snap?.title || catalog?.section || sectionId, subtitle: snap?.subtitle || catalog?.subtitle || '' })
    setCatImgPrev(snap?.imageBase64 ? imgSrc(snap.imageBase64) : (CATALOG_FALLBACK_IMAGES[sectionId] || null))
    setCatImgB64(null); setCatRemoveImg(false)
  }
  async function onCatImgChange(e) {
    const f = e.target.files?.[0]; if (!f) return
    const b64 = await fileToBase64(f); setCatImgB64(b64); setCatImgPrev(imgSrc(b64)); setCatRemoveImg(false)
  }
  async function handleEditCatSave(e) {
    e.preventDefault(); if (!editCat) return
    setBusy('cat')
    try {
      const existing    = getCatSnap(editCat) || {}
      const imageBase64 = catRemoveImg ? null : (catImgB64 || existing.imageBase64 || null)
      await saveSecSnap(editCat, { title: catForm.title.trim(), subtitle: catForm.subtitle.trim(), imageBase64 })
      setEditCat(null)
    } finally { setBusy(null) }
  }

  async function handleAddCat(e) {
    e.preventDefault()
    const name = newCatName.trim(); if (!name) return
    if (meta.customCategoryIds.includes(name)) { alert('Category already exists'); return }
    setBusy('addCat')
    try {
      await setDoc(MENU_DOC, { customCategoryIds: arrayUnion(name), customCategoryIdsUpdatedAt: serverTimestamp() }, { merge: true })
      setAddCatOpen(false); setNewCatName(''); setTab(name)
    } finally { setBusy(null) }
  }

  async function handleAddDish(e) {
    e.preventDefault()
    const section = addDishSec; if (!section || !newDish.title.trim()) return
    const key = `${CUSTOM_PREFIX}${section}${SEP}${Date.now()}`
    setBusy('addDish')
    try {
      await saveDishSnap(key, { title: newDish.title.trim(), subtitle: newDish.subtitle.trim(),
        price: newDish.price.trim() || '', badge: newDish.badge.trim() || null,
        available: true, imageBase64: newDishImgB64 || null })
      setAddDishSec(null); setNewDish(emptyDish); setNewDishImgB64(null); setNewDishImgPrev(null)
    } finally { setBusy(null) }
  }
  async function onNewDishImgChange(e) {
    const f = e.target.files?.[0]; if (!f) return
    const b64 = await fileToBase64(f); setNewDishImgB64(b64); setNewDishImgPrev(imgSrc(b64))
  }

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Menu</h1>
          <p className="page-subtitle">
            {allDishes.length} dishes &nbsp;·&nbsp; {availCount} available &nbsp;·&nbsp; {allDishes.length - availCount} unavailable
          </p>
        </div>
        <div className="flex gap-3">
          <input className="input max-w-xs" placeholder="Search dishes..." value={search} onChange={e => setSearch(e.target.value)} />
          <button
            onClick={() => setAddDishSec(tab === 'All' ? (allTabs[1] || null) : tab)}
            disabled={allTabs.length < 2}
            className="btn-primary whitespace-nowrap disabled:opacity-50"
          >
            + Add Dish
          </button>
          <button onClick={() => setAddCatOpen(true)} className="btn-ghost whitespace-nowrap">+ Add Category</button>
        </div>
      </div>

      {/* Section tabs */}
      <div className="flex gap-2 flex-wrap">
        {allTabs.map(s => (
          <button key={s} onClick={() => setTab(s)}
            className={`px-4 py-1.5 rounded-xl text-sm font-semibold transition-all ${tab === s ? 'bg-maroon text-white shadow-sm' : 'bg-white border border-cream-border text-gray-600 hover:bg-cream'}`}>
            {s === 'All' ? s : getCatTitle(s)}
            {customTabs.includes(s) && <span className="ml-1 text-[10px] opacity-50">custom</span>}
          </button>
        ))}
      </div>

      {/* Category info card */}
      {tab !== 'All' && (
        <div className="section-card overflow-hidden">
          <div className="flex flex-col sm:flex-row">
            <div className="flex-1 p-5 flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <h2 className="font-display font-bold text-xl text-maroon-deep">{getCatTitle(tab)}</h2>
                  {isCustomTab && <span className="badge bg-amber-50 text-amber-700 border border-amber-200 text-xs">Custom</span>}
                </div>
                <p className="text-sm text-gray-500 mt-1">{getCatSubtitle(tab) || 'No subtitle set'}</p>
                <p className="text-xs text-gray-400 mt-1 font-mono">Section ID: {tab}</p>
              </div>
              <div className="flex gap-2 mt-4 flex-wrap">
                <button onClick={() => openEditCat(tab)} className="btn-primary text-xs py-2 px-4">
                  Edit Category
                </button>
                <button onClick={() => setAddDishSec(tab)} className="btn-ghost text-xs py-2 px-4">+ Add Dish</button>
                {isCustomTab && (
                  <button onClick={() => deleteSection(tab)} className="text-xs px-4 py-2 rounded-xl bg-red-50 text-red-700 border border-red-100 font-semibold hover:bg-red-100 transition-colors">Delete Category</button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Dish table */}
      <div className="section-card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-cream/60 border-b border-cream-border">
                {['Dish', 'Category', 'Price', 'Badge', 'Status', 'Actions'].map(h => (
                  <th key={h} className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map(dish => (
                <tr key={dish.key} className={`table-row ${!dish.available ? 'opacity-50' : ''}`}>
                  <td className="px-5 py-3.5">
                    <div className="flex items-center gap-3">
                      {dish.imageBase64
                        ? <img src={imgSrc(dish.imageBase64)} alt={dish.title} className="w-10 h-10 rounded-lg object-cover shrink-0 border border-cream-border" />
                        : <div className="w-10 h-10 rounded-lg bg-cream flex items-center justify-center shrink-0">
                            <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5 text-gray-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                            </svg>
                          </div>
                      }
                      <div>
                        <p className="font-semibold text-gray-900">{dish.title}</p>
                        <p className="text-xs text-gray-500">{dish.subtitle}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-3.5 text-xs text-gray-500">{getCatTitle(dish.section)}{dish.isCustom ? ' (custom)' : ''}</td>
                  <td className="px-5 py-3.5 font-bold text-maroon-deep">{dish.price}</td>
                  <td className="px-5 py-3.5">
                    {dish.badge
                      ? <span className="badge bg-amber-50 text-amber-700 border border-amber-200">{dish.badge}</span>
                      : <span className="text-gray-300 text-xs">-</span>}
                  </td>
                  <td className="px-5 py-3.5">
                    <button onClick={() => toggleAvail(dish)} disabled={busy === dish.key}
                      className={`flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors ${dish.available ? 'bg-green-50 text-green-700 hover:bg-green-100' : 'bg-red-50 text-red-600 hover:bg-red-100'}`}>
                      {busy === dish.key
                        ? <span className="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                        : <span className={`w-2 h-2 rounded-full ${dish.available ? 'bg-green-500' : 'bg-red-400'}`} />}
                      {dish.available ? 'Available' : 'Unavailable'}
                    </button>
                  </td>
                  <td className="px-5 py-3.5">
                    <div className="flex gap-2">
                      <button onClick={() => openEditDish(dish)} className="text-xs px-3 py-1.5 rounded-lg bg-cream border border-cream-border text-gray-700 hover:bg-cream-border transition-colors font-semibold">Edit</button>
                      <button onClick={() => deleteDish(dish)} disabled={busy === dish.key}
                        className="text-xs px-3 py-1.5 rounded-lg bg-red-50 border border-red-100 text-red-600 hover:bg-red-100 transition-colors font-semibold">Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr><td colSpan={6} className="px-6 py-12 text-center text-gray-400 text-sm">
                  {tab !== 'All' && isCustomTab
                    ? <span>No dishes yet. <button onClick={() => setAddDishSec(tab)} className="text-maroon font-semibold underline">Add the first dish</button></span>
                    : 'No dishes found'}
                </td></tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
          Showing {filtered.length} dishes
        </div>
      </div>

      {/* Edit Dish Modal */}
      {editDish && (
        <Modal title="Edit Dish" onClose={() => setEditDish(null)}>
          <form onSubmit={handleEditDishSave} className="space-y-4">
            <ImageUploadBox preview={dishImgPrev} inputRef={dishImgRef}
              onClear={() => { setDishImgPrev(null); setDishImgB64(null) }}
              onChange={onDishImgChange} label="Dish Photo" />
            <Field label="Dish Name">
              <input className="input" value={dishForm.title} onChange={e => setDishForm({ ...dishForm, title: e.target.value })} required />
            </Field>
            <Field label="Subtitle">
              <input className="input" value={dishForm.subtitle} onChange={e => setDishForm({ ...dishForm, subtitle: e.target.value })} />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field label="Price">
                <input className="input" value={dishForm.price} onChange={e => setDishForm({ ...dishForm, price: e.target.value })} placeholder="Rs. 70" required />
              </Field>
              <Field label="Badge">
                <input className="input" value={dishForm.badge} onChange={e => setDishForm({ ...dishForm, badge: e.target.value })} placeholder="Bestseller" />
              </Field>
            </div>
            <label className="flex items-center gap-3 cursor-pointer">
              <input type="checkbox" checked={dishForm.available} onChange={e => setDishForm({ ...dishForm, available: e.target.checked })} className="w-4 h-4 accent-maroon" />
              <span className="text-sm font-semibold text-gray-700">Available to order</span>
            </label>
            <ModalActions onCancel={() => setEditDish(null)} saving={!!busy} label="Save Changes" />
          </form>
        </Modal>
      )}

      {/* Edit Category Modal */}
      {editCat && (
        <Modal title="Edit Category" onClose={() => setEditCat(null)}>
          <form onSubmit={handleEditCatSave} className="space-y-4">
            <Field label="Category Name">
              <input className="input" value={catForm.title} onChange={e => setCatForm({ ...catForm, title: e.target.value })} required placeholder={editCat} />
            </Field>
            <Field label="Subtitle (shown to customers)">
              <input className="input" value={catForm.subtitle} onChange={e => setCatForm({ ...catForm, subtitle: e.target.value })} placeholder="Short description under category name" />
            </Field>
            <ModalActions onCancel={() => setEditCat(null)} saving={busy === 'cat'} label="Save Category" />
          </form>
        </Modal>
      )}

      {/* Add Category Modal */}
      {addCatOpen && (
        <Modal title="Add New Category" onClose={() => setAddCatOpen(false)}>
          <form onSubmit={handleAddCat} className="space-y-4">
            <Field label="Category Name">
              <input className="input" value={newCatName} onChange={e => setNewCatName(e.target.value)} placeholder="e.g. Breakfast Specials" required autoFocus />
              <p className="text-xs text-gray-400 mt-1">Appears as a new section in the app and web.</p>
            </Field>
            <ModalActions onCancel={() => setAddCatOpen(false)} saving={busy === 'addCat'} label="Add Category" />
          </form>
        </Modal>
      )}

      {/* Add Dish Modal */}
      {addDishSec && (
        <Modal title={`Add Dish - ${getCatTitle(addDishSec)}`} onClose={() => setAddDishSec(null)}>
          <form onSubmit={handleAddDish} className="space-y-4">
            <ImageUploadBox preview={newDishImgPrev} inputRef={newDishImgRef}
              onClear={() => { setNewDishImgPrev(null); setNewDishImgB64(null) }}
              onChange={onNewDishImgChange} label="Dish Photo" />
            <Field label="Dish Name *">
              <input className="input" value={newDish.title} onChange={e => setNewDish({ ...newDish, title: e.target.value })} required autoFocus />
            </Field>
            <Field label="Subtitle">
              <input className="input" value={newDish.subtitle} onChange={e => setNewDish({ ...newDish, subtitle: e.target.value })} placeholder="Short description" />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field label="Price *">
                <input className="input" value={newDish.price} onChange={e => setNewDish({ ...newDish, price: e.target.value })} placeholder="Rs. 70" required />
              </Field>
              <Field label="Badge">
                <input className="input" value={newDish.badge} onChange={e => setNewDish({ ...newDish, badge: e.target.value })} placeholder="New" />
              </Field>
            </div>
            <ModalActions onCancel={() => setAddDishSec(null)} saving={busy === 'addDish'} label="Add Dish" />
          </form>
        </Modal>
      )}
    </div>
  )
}

function Modal({ title, onClose, children }) {
  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md max-h-[90vh] overflow-y-auto">
        <div className="px-6 py-5 border-b border-cream-border flex items-center justify-between sticky top-0 bg-white rounded-t-2xl z-10">
          <h2 className="font-display font-bold text-xl text-maroon-deep">{title}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">&times;</button>
        </div>
        <div className="p-6">{children}</div>
      </div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div>
      <label className="block text-sm font-semibold text-gray-700 mb-1.5">{label}</label>
      {children}
    </div>
  )
}

function ModalActions({ onCancel, saving, label }) {
  return (
    <div className="flex gap-3 pt-2">
      <button type="button" onClick={onCancel} className="btn-ghost flex-1">Cancel</button>
      <button type="submit" disabled={saving} className="btn-primary flex-1">
        {saving
          ? <span className="flex items-center justify-center gap-2">
              <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> Saving...
            </span>
          : label}
      </button>
    </div>
  )
}

function ImageUploadBox({ preview, inputRef, onClear, onChange, label }) {
  return (
    <div>
      <label className="block text-sm font-semibold text-gray-700 mb-2">{label}</label>
      <div className="flex items-center gap-4">
        <div className="w-20 h-20 rounded-xl border-2 border-dashed border-cream-border flex items-center justify-center overflow-hidden cursor-pointer hover:border-maroon transition-colors bg-cream shrink-0"
          onClick={() => inputRef.current?.click()}>
          {preview
            ? <img src={preview} alt="" className="w-full h-full object-cover" />
            : <svg xmlns="http://www.w3.org/2000/svg" className="w-6 h-6 text-gray-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>}
        </div>
        <div>
          <button type="button" onClick={() => inputRef.current?.click()} className="btn-ghost text-xs py-2 px-4">
            {preview ? 'Change Photo' : 'Upload Photo'}
          </button>
          {preview && <button type="button" onClick={onClear} className="ml-2 text-xs text-red-500 hover:text-red-700 font-semibold">Remove</button>}
          <p className="text-xs text-gray-400 mt-1">JPG or PNG</p>
        </div>
      </div>
      <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={onChange} />
    </div>
  )
}
