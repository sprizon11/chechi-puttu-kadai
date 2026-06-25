import { useEffect, useState, useRef } from 'react'
import {
  collection, doc, onSnapshot, setDoc, updateDoc,
  arrayUnion, arrayRemove, serverTimestamp, query, getDoc
} from 'firebase/firestore'
import { db } from '../firebase'
import { CATALOG, dishKey, allCatalogDishes } from '../catalog'

const SEP = '' //  — same separator as Flutter
const CUSTOM_PREFIX = '__custom__'
const SECTION_KEY_PREFIX = '__section__'

function keyToDocId(key) {
  const bytes = new TextEncoder().encode(key)
  let binary = ''
  bytes.forEach(b => binary += String.fromCharCode(b))
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result.split(',')[1])
    reader.onerror = reject
    reader.readAsDataURL(file)
  })
}

const MENU_DOC = doc(db, 'admin_public', 'menu_overrides')
const snapsColl = collection(db, 'admin_public', 'menu_overrides', 'snapshots')
const sectionSnapsColl = collection(db, 'admin_public', 'menu_overrides', 'section_snapshots')

export default function Menu() {
  const [menuMeta, setMenuMeta] = useState({ deletedDishKeys: [], deletedSectionIds: [], customCategoryIds: [] })
  const [snapshots, setSnapshots] = useState({})       // dishKey → data
  const [sectionSnaps, setSectionSnaps] = useState({}) // __section__sectionId → data
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [activeSection, setActiveSection] = useState('All')
  const [saving, setSaving] = useState(null)

  // Modals
  const [editDish, setEditDish] = useState(null)
  const [editForm, setEditForm] = useState({})
  const [editImagePreview, setEditImagePreview] = useState(null)
  const [editImageB64, setEditImageB64] = useState(null)

  const [addCatOpen, setAddCatOpen] = useState(false)
  const [newCatName, setNewCatName] = useState('')

  const [addDishOpen, setAddDishOpen] = useState(null) // section name
  const [newDish, setNewDish] = useState({ title: '', subtitle: '', price: '', badge: '' })
  const [newDishImageB64, setNewDishImageB64] = useState(null)
  const [newDishImagePreview, setNewDishImagePreview] = useState(null)

  const editImageRef = useRef()
  const newDishImageRef = useRef()

  // ── Load Firestore ──────────────────────────────────────────────────────────
  useEffect(() => {
    let loaded = 0
    const done = () => { if (++loaded >= 3) setLoading(false) }

    const u1 = onSnapshot(MENU_DOC, snap => {
      const d = snap.data() || {}
      setMenuMeta({
        deletedDishKeys: d.deletedDishKeys || [],
        deletedSectionIds: d.deletedSectionIds || [],
        customCategoryIds: d.customCategoryIds || [],
      })
      done()
    })
    const u2 = onSnapshot(query(snapsColl), snap => {
      const map = {}
      snap.docs.forEach(d => {
        const { key, data } = d.data()
        if (key) map[key] = { ...data, _docId: d.id }
      })
      setSnapshots(map)
      done()
    })
    const u3 = onSnapshot(query(sectionSnapsColl), snap => {
      const map = {}
      snap.docs.forEach(d => {
        const { key, data } = d.data()
        if (key) map[key] = { ...data, _docId: d.id }
      })
      setSectionSnaps(map)
      done()
    })
    return () => { u1(); u2(); u3() }
  }, [])

  // ── Build dish list ─────────────────────────────────────────────────────────
  const deletedSet = new Set(menuMeta.deletedDishKeys)
  const deletedSections = new Set(menuMeta.deletedSectionIds)

  // Catalog dishes (excluding deleted + deleted sections)
  const catalogDishes = allCatalogDishes()
    .filter(d => !deletedSections.has(d.section) && !deletedSet.has(d.key))
    .map(d => {
      const ov = snapshots[d.key] || {}
      return {
        ...d,
        title: ov.title || d.title,
        subtitle: ov.subtitle || d.subtitle,
        price: ov.price || d.price,
        badge: ov.badge !== undefined ? ov.badge : d.badge,
        available: ov.available !== undefined ? ov.available : true,
        imageBase64: ov.imageBase64 || null,
        isCustom: false,
      }
    })

  // Custom category dishes
  const customDishes = []
  menuMeta.customCategoryIds.forEach(catId => {
    if (deletedSections.has(catId)) return
    const prefix = `${CUSTOM_PREFIX}${catId}${SEP}`
    Object.entries(snapshots).forEach(([k, data]) => {
      if (!k.startsWith(prefix)) return
      if (deletedSet.has(k)) return
      customDishes.push({
        key: k,
        section: catId,
        title: data.title || '',
        subtitle: data.subtitle || '',
        price: data.price || '₹0',
        badge: data.badge || null,
        available: data.available !== undefined ? data.available : true,
        imageBase64: data.imageBase64 || null,
        isCustom: true,
      })
    })
  })

  const allDishes = [...catalogDishes, ...customDishes]
  const availableCount = allDishes.filter(d => d.available).length

  // Section tabs — catalog sections + custom categories
  const catalogSectionTabs = CATALOG.map(s => s.section).filter(s => !deletedSections.has(s))
  const customSectionTabs = menuMeta.customCategoryIds.filter(c => !deletedSections.has(c))
  const sectionTabs = ['All', ...catalogSectionTabs, ...customSectionTabs]

  const filtered = allDishes.filter(d => {
    const matchSec = activeSection === 'All' || d.section === activeSection
    const matchQ = !search || d.title.toLowerCase().includes(search.toLowerCase()) || d.subtitle.toLowerCase().includes(search.toLowerCase())
    return matchSec && matchQ
  })

  // ── Helpers ─────────────────────────────────────────────────────────────────
  async function saveDishSnapshot(key, data) {
    const docId = keyToDocId(key)
    await setDoc(doc(snapsColl, docId), { key, data, updated_at: serverTimestamp() }, { merge: true })
  }

  async function toggleAvailable(dish) {
    setSaving(dish.key)
    try {
      const existing = snapshots[dish.key] || {}
      await saveDishSnapshot(dish.key, {
        title: dish.title, subtitle: dish.subtitle, price: dish.price,
        badge: dish.badge || null, available: !dish.available,
        imageBase64: dish.imageBase64 || null, ...existing,
        available: !dish.available,
      })
    } finally { setSaving(null) }
  }

  async function deleteDish(dish) {
    if (!confirm(`Hide "${dish.title}" from the menu?\n\nCustomers will not see it. You can restore it from the app.`)) return
    setSaving(dish.key)
    try {
      await updateDoc(MENU_DOC, { deletedDishKeys: arrayUnion(dish.key), deletedDishKeysUpdatedAt: serverTimestamp() })
    } finally { setSaving(null) }
  }

  async function deleteSection(sectionId) {
    if (!confirm(`Delete the entire "${sectionId}" category?\n\nAll its dishes will be hidden from customers.`)) return
    await updateDoc(MENU_DOC, { deletedSectionIds: arrayUnion(sectionId) })
    if (activeSection === sectionId) setActiveSection('All')
  }

  // ── Edit dish ───────────────────────────────────────────────────────────────
  function openEdit(dish) {
    setEditDish(dish)
    setEditForm({ title: dish.title, subtitle: dish.subtitle, price: dish.price, badge: dish.badge || '', available: dish.available })
    setEditImagePreview(dish.imageBase64 ? `data:image/jpeg;base64,${dish.imageBase64}` : null)
    setEditImageB64(null)
  }

  async function handleEditImageChange(e) {
    const file = e.target.files?.[0]
    if (!file) return
    const b64 = await fileToBase64(file)
    setEditImageB64(b64)
    setEditImagePreview(`data:image/${file.type.split('/')[1]};base64,${b64}`)
  }

  async function handleEditSave(e) {
    e.preventDefault()
    if (!editDish) return
    setSaving(editDish.key)
    try {
      const existing = snapshots[editDish.key] || {}
      await saveDishSnapshot(editDish.key, {
        ...existing,
        title: editForm.title.trim(),
        subtitle: editForm.subtitle.trim(),
        price: editForm.price.trim(),
        badge: editForm.badge.trim() || null,
        available: editForm.available,
        imageBase64: editImageB64 || existing.imageBase64 || null,
      })
      setEditDish(null)
    } finally { setSaving(null) }
  }

  // ── Add category ─────────────────────────────────────────────────────────────
  async function handleAddCategory(e) {
    e.preventDefault()
    const name = newCatName.trim()
    if (!name) return
    if (menuMeta.customCategoryIds.includes(name)) { alert('Category already exists'); return }
    setSaving('addCat')
    try {
      await setDoc(MENU_DOC, { customCategoryIds: arrayUnion(name), customCategoryIdsUpdatedAt: serverTimestamp() }, { merge: true })
      setAddCatOpen(false)
      setNewCatName('')
      setActiveSection(name)
    } finally { setSaving(null) }
  }

  // ── Add custom dish ───────────────────────────────────────────────────────────
  async function handleAddDish(e) {
    e.preventDefault()
    const section = addDishOpen
    if (!section || !newDish.title.trim()) return
    const dishId = `${Date.now()}`
    const key = `${CUSTOM_PREFIX}${section}${SEP}${dishId}`
    setSaving('addDish')
    try {
      await saveDishSnapshot(key, {
        title: newDish.title.trim(),
        subtitle: newDish.subtitle.trim(),
        price: newDish.price.trim() || '₹0',
        badge: newDish.badge.trim() || null,
        available: true,
        imageBase64: newDishImageB64 || null,
      })
      setAddDishOpen(null)
      setNewDish({ title: '', subtitle: '', price: '', badge: '' })
      setNewDishImageB64(null)
      setNewDishImagePreview(null)
    } finally { setSaving(null) }
  }

  async function handleNewDishImageChange(e) {
    const file = e.target.files?.[0]
    if (!file) return
    const b64 = await fileToBase64(file)
    setNewDishImageB64(b64)
    setNewDishImagePreview(`data:image/${file.type.split('/')[1]};base64,${b64}`)
  }

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  const isCustomSection = customSectionTabs.includes(activeSection)

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Menu</h1>
          <p className="page-subtitle">{allDishes.length} dishes · {availableCount} available · {allDishes.length - availableCount} unavailable</p>
        </div>
        <div className="flex gap-3">
          <input className="input max-w-xs" placeholder="Search dishes…" value={search} onChange={e => setSearch(e.target.value)} />
          <button onClick={() => setAddCatOpen(true)} className="btn-primary whitespace-nowrap">+ Add Category</button>
        </div>
      </div>

      {/* Section tabs */}
      <div className="flex gap-2 flex-wrap items-center">
        {sectionTabs.map(s => (
          <button
            key={s}
            onClick={() => setActiveSection(s)}
            className={`px-4 py-1.5 rounded-xl text-sm font-semibold transition-all ${
              activeSection === s ? 'bg-maroon text-white shadow-sm' : 'bg-white border border-cream-border text-gray-600 hover:bg-cream'
            }`}
          >
            {s}
            {customSectionTabs.includes(s) && <span className="ml-1 text-xs opacity-60">✦</span>}
          </button>
        ))}
      </div>

      {/* "Add Dish" button for custom sections */}
      {activeSection !== 'All' && isCustomSection && (
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-500 font-semibold">Custom category</span>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setAddDishOpen(activeSection)} className="btn-primary text-xs py-2">+ Add Dish</button>
            <button onClick={() => deleteSection(activeSection)} className="text-xs px-3 py-2 rounded-xl bg-red-50 text-red-700 border border-red-100 font-semibold hover:bg-red-100 transition-colors">Delete Category</button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="section-card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-cream/60 border-b border-cream-border">
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Dish</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Category</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Price</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Badge</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(dish => (
                <tr key={dish.key} className={`table-row ${!dish.available ? 'opacity-50' : ''}`}>
                  <td className="px-5 py-3.5">
                    <div className="flex items-center gap-3">
                      {dish.imageBase64
                        ? <img src={`data:image/jpeg;base64,${dish.imageBase64}`} alt={dish.title} className="w-10 h-10 rounded-lg object-cover shrink-0 border border-cream-border" />
                        : <div className="w-10 h-10 rounded-lg bg-cream flex items-center justify-center text-lg shrink-0">🍽️</div>
                      }
                      <div>
                        <p className="font-semibold text-gray-900">{dish.title}</p>
                        <p className="text-xs text-gray-500">{dish.subtitle}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-3.5 text-gray-500 text-xs">{dish.section}{dish.isCustom ? ' ✦' : ''}</td>
                  <td className="px-5 py-3.5 font-bold text-maroon-deep">{dish.price}</td>
                  <td className="px-5 py-3.5">
                    {dish.badge
                      ? <span className="badge bg-amber-50 text-amber-700 border border-amber-200">{dish.badge}</span>
                      : <span className="text-gray-300 text-xs">—</span>
                    }
                  </td>
                  <td className="px-5 py-3.5">
                    <button
                      onClick={() => toggleAvailable(dish)}
                      disabled={saving === dish.key}
                      className={`flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors ${
                        dish.available ? 'bg-green-50 text-green-700 hover:bg-green-100' : 'bg-red-50 text-red-600 hover:bg-red-100'
                      }`}
                    >
                      {saving === dish.key
                        ? <span className="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                        : <span className={`w-2 h-2 rounded-full ${dish.available ? 'bg-green-500' : 'bg-red-400'}`} />
                      }
                      {dish.available ? 'Available' : 'Unavailable'}
                    </button>
                  </td>
                  <td className="px-5 py-3.5">
                    <div className="flex gap-2">
                      <button onClick={() => openEdit(dish)} className="text-xs px-3 py-1.5 rounded-lg bg-cream border border-cream-border text-gray-700 hover:bg-cream-border transition-colors font-semibold">Edit</button>
                      <button
                        onClick={() => deleteDish(dish)}
                        disabled={saving === dish.key}
                        className="text-xs px-3 py-1.5 rounded-lg bg-red-50 border border-red-100 text-red-600 hover:bg-red-100 transition-colors font-semibold"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center text-gray-400 text-sm">
                    {activeSection !== 'All' && isCustomSection
                      ? <span>No dishes yet. <button onClick={() => setAddDishOpen(activeSection)} className="text-maroon font-semibold underline">Add the first dish →</button></span>
                      : 'No dishes found'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
          Showing {filtered.length} dishes · ✦ = custom category
        </div>
      </div>

      {/* ── Edit Dish Modal ── */}
      {editDish && (
        <Modal title="Edit Dish" onClose={() => setEditDish(null)}>
          <form onSubmit={handleEditSave} className="space-y-4">
            {/* Image */}
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Image</label>
              <div className="flex items-center gap-4">
                <div
                  className="w-20 h-20 rounded-xl border-2 border-dashed border-cream-border flex items-center justify-center overflow-hidden cursor-pointer hover:border-maroon transition-colors bg-cream"
                  onClick={() => editImageRef.current?.click()}
                >
                  {editImagePreview
                    ? <img src={editImagePreview} alt="" className="w-full h-full object-cover" />
                    : <span className="text-2xl">📷</span>
                  }
                </div>
                <div>
                  <button type="button" onClick={() => editImageRef.current?.click()} className="btn-ghost text-xs py-2 px-4">
                    {editImagePreview ? 'Change Photo' : 'Upload Photo'}
                  </button>
                  {editImagePreview && (
                    <button type="button" onClick={() => { setEditImagePreview(null); setEditImageB64(null) }} className="ml-2 text-xs text-red-500 hover:text-red-700">Remove</button>
                  )}
                  <p className="text-xs text-gray-400 mt-1">JPG or PNG, max 1MB</p>
                </div>
              </div>
              <input ref={editImageRef} type="file" accept="image/*" className="hidden" onChange={handleEditImageChange} />
            </div>

            <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Name</label><input className="input" value={editForm.title} onChange={e => setEditForm({ ...editForm, title: e.target.value })} required /></div>
            <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Subtitle</label><input className="input" value={editForm.subtitle} onChange={e => setEditForm({ ...editForm, subtitle: e.target.value })} /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Price</label><input className="input" value={editForm.price} onChange={e => setEditForm({ ...editForm, price: e.target.value })} placeholder="₹70" required /></div>
              <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Badge</label><input className="input" value={editForm.badge} onChange={e => setEditForm({ ...editForm, badge: e.target.value })} placeholder="Bestseller" /></div>
            </div>
            <div className="flex items-center gap-3">
              <input type="checkbox" id="edit-avail" checked={editForm.available} onChange={e => setEditForm({ ...editForm, available: e.target.checked })} className="w-4 h-4 accent-maroon" />
              <label htmlFor="edit-avail" className="text-sm font-semibold text-gray-700">Available to order</label>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setEditDish(null)} className="btn-ghost flex-1">Cancel</button>
              <button type="submit" disabled={!!saving} className="btn-primary flex-1">{saving ? 'Saving…' : 'Save Changes'}</button>
            </div>
          </form>
        </Modal>
      )}

      {/* ── Add Category Modal ── */}
      {addCatOpen && (
        <Modal title="Add New Category" onClose={() => setAddCatOpen(false)}>
          <form onSubmit={handleAddCategory} className="space-y-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">Category Name</label>
              <input className="input" value={newCatName} onChange={e => setNewCatName(e.target.value)} placeholder="e.g. Breakfast Specials" required autoFocus />
              <p className="text-xs text-gray-400 mt-1.5">This will appear as a new section in the app and web.</p>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setAddCatOpen(false)} className="btn-ghost flex-1">Cancel</button>
              <button type="submit" disabled={saving === 'addCat'} className="btn-primary flex-1">{saving === 'addCat' ? 'Adding…' : 'Add Category'}</button>
            </div>
          </form>
        </Modal>
      )}

      {/* ── Add Dish Modal ── */}
      {addDishOpen && (
        <Modal title={`Add Dish — ${addDishOpen}`} onClose={() => setAddDishOpen(null)}>
          <form onSubmit={handleAddDish} className="space-y-4">
            {/* Image */}
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Image</label>
              <div className="flex items-center gap-4">
                <div
                  className="w-20 h-20 rounded-xl border-2 border-dashed border-cream-border flex items-center justify-center overflow-hidden cursor-pointer hover:border-maroon transition-colors bg-cream"
                  onClick={() => newDishImageRef.current?.click()}
                >
                  {newDishImagePreview ? <img src={newDishImagePreview} alt="" className="w-full h-full object-cover" /> : <span className="text-2xl">📷</span>}
                </div>
                <button type="button" onClick={() => newDishImageRef.current?.click()} className="btn-ghost text-xs py-2 px-4">Upload Photo</button>
              </div>
              <input ref={newDishImageRef} type="file" accept="image/*" className="hidden" onChange={handleNewDishImageChange} />
            </div>

            <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Name *</label><input className="input" value={newDish.title} onChange={e => setNewDish({ ...newDish, title: e.target.value })} required autoFocus /></div>
            <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Subtitle</label><input className="input" value={newDish.subtitle} onChange={e => setNewDish({ ...newDish, subtitle: e.target.value })} placeholder="Short description" /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Price *</label><input className="input" value={newDish.price} onChange={e => setNewDish({ ...newDish, price: e.target.value })} placeholder="₹70" required /></div>
              <div><label className="block text-sm font-semibold text-gray-700 mb-1.5">Badge</label><input className="input" value={newDish.badge} onChange={e => setNewDish({ ...newDish, badge: e.target.value })} placeholder="New" /></div>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setAddDishOpen(null)} className="btn-ghost flex-1">Cancel</button>
              <button type="submit" disabled={saving === 'addDish'} className="btn-primary flex-1">{saving === 'addDish' ? 'Adding…' : 'Add Dish'}</button>
            </div>
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
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
        </div>
        <div className="p-6">{children}</div>
      </div>
    </div>
  )
}
