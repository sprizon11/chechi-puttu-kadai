import { useEffect, useState } from 'react'
import {
  collection, doc, onSnapshot, setDoc, serverTimestamp, query
} from 'firebase/firestore'
import { db } from '../firebase'
import { CATALOG, dishKey, allCatalogDishes } from '../catalog'

const SEP = ''

function parseKey(key) {
  const idx = key.indexOf(SEP)
  if (idx === -1) return { section: '', title: key }
  return { section: key.slice(0, idx), title: key.slice(idx + 1) }
}

export default function Menu() {
  const [snapshots, setSnapshots] = useState({})   // key → data
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [activeSection, setActiveSection] = useState('All')
  const [saving, setSaving] = useState(null)
  const [editItem, setEditItem] = useState(null)
  const [editForm, setEditForm] = useState({})

  // Load all dish snapshots from admin_public/menu_overrides/snapshots
  useEffect(() => {
    const ref = collection(db, 'admin_public', 'menu_overrides', 'snapshots')
    return onSnapshot(query(ref), snap => {
      const map = {}
      snap.docs.forEach(d => {
        const { key, data } = d.data()
        if (key) map[key] = { ...data, _docId: d.id }
      })
      setSnapshots(map)
      setLoading(false)
    })
  }, [])

  // Merge catalog with Firestore overrides
  const catalog = allCatalogDishes()
  const merged = catalog.map(dish => {
    const override = snapshots[dish.key] || {}
    return {
      ...dish,
      title: override.title || dish.title,
      subtitle: override.subtitle || dish.subtitle,
      price: override.price || dish.price,
      badge: override.badge !== undefined ? override.badge : dish.badge,
      available: override.available !== undefined ? override.available : true,
      imageBase64: override.imageBase64 || null,
      hasOverride: !!snapshots[dish.key],
    }
  })

  // Also add any custom dishes (keys with __custom__ prefix not in catalog)
  const catalogKeys = new Set(catalog.map(d => d.key))
  const customDishes = Object.entries(snapshots)
    .filter(([k]) => !catalogKeys.has(k) && !k.startsWith('__section__'))
    .map(([k, data]) => {
      const { section, title } = parseKey(k)
      return {
        key: k,
        section: section || 'Custom',
        title: data.title || title,
        subtitle: data.subtitle || '',
        price: data.price || '₹0',
        badge: data.badge || null,
        available: data.available !== undefined ? data.available : true,
        imageBase64: data.imageBase64 || null,
        hasOverride: true,
      }
    })

  const allDishes = [...merged, ...customDishes]

  const sections = ['All', ...CATALOG.map(s => s.section)]
  if (customDishes.length > 0 && !sections.includes('Custom')) sections.push('Custom')

  const filtered = allDishes.filter(d => {
    const matchSection = activeSection === 'All' || d.section === activeSection
    const matchSearch = !search ||
      d.title.toLowerCase().includes(search.toLowerCase()) ||
      d.subtitle.toLowerCase().includes(search.toLowerCase())
    return matchSection && matchSearch
  })

  const availableCount = allDishes.filter(d => d.available).length

  async function toggleAvailable(dish) {
    const newVal = !dish.available
    setSaving(dish.key)
    try {
      await saveSnapshot(dish.key, dish, { available: newVal })
    } finally {
      setSaving(null)
    }
  }

  async function saveSnapshot(key, base, patch) {
    const existing = snapshots[key]
    const data = {
      title: base.title,
      subtitle: base.subtitle,
      price: base.price,
      badge: base.badge || null,
      available: base.available,
      imageBase64: base.imageBase64 || null,
      ...patch,
    }
    const docId = existing?._docId || key.replace(/[^a-zA-Z0-9_-]/g, '_')
    await setDoc(
      doc(db, 'admin_public', 'menu_overrides', 'snapshots', docId),
      { key, data, updatedAt: serverTimestamp() },
      { merge: true }
    )
  }

  function openEdit(dish) {
    setEditItem(dish)
    setEditForm({
      title: dish.title,
      subtitle: dish.subtitle,
      price: dish.price,
      badge: dish.badge || '',
      available: dish.available,
    })
  }

  async function handleEditSave(e) {
    e.preventDefault()
    if (!editItem) return
    setSaving(editItem.key)
    try {
      await saveSnapshot(editItem.key, editItem, {
        title: editForm.title.trim(),
        subtitle: editForm.subtitle.trim(),
        price: editForm.price.trim(),
        badge: editForm.badge.trim() || null,
        available: editForm.available,
      })
      setEditItem(null)
    } finally {
      setSaving(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Menu</h1>
          <p className="page-subtitle">
            {allDishes.length} dishes · {availableCount} available · {allDishes.length - availableCount} unavailable
          </p>
        </div>
        <input
          className="input max-w-xs"
          placeholder="Search dishes…"
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
      </div>

      {/* Section tabs */}
      <div className="flex gap-2 flex-wrap">
        {sections.map(s => (
          <button
            key={s}
            onClick={() => setActiveSection(s)}
            className={`px-4 py-1.5 rounded-xl text-sm font-semibold transition-all ${
              activeSection === s
                ? 'bg-maroon text-white shadow-sm'
                : 'bg-white border border-cream-border text-gray-600 hover:bg-cream'
            }`}
          >
            {s}
          </button>
        ))}
      </div>

      {/* Dish table */}
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
                      {dish.imageBase64 ? (
                        <img
                          src={`data:image/jpeg;base64,${dish.imageBase64}`}
                          alt={dish.title}
                          className="w-10 h-10 rounded-lg object-cover shrink-0 border border-cream-border"
                        />
                      ) : (
                        <div className="w-10 h-10 rounded-lg bg-cream flex items-center justify-center text-lg shrink-0">🍽️</div>
                      )}
                      <div>
                        <p className="font-semibold text-gray-900">{dish.title}</p>
                        <p className="text-xs text-gray-500">{dish.subtitle}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-3.5 text-gray-600 text-xs">{dish.section}</td>
                  <td className="px-5 py-3.5 font-bold text-maroon-deep">{dish.price}</td>
                  <td className="px-5 py-3.5">
                    {dish.badge ? (
                      <span className="badge bg-amber-50 text-amber-700 border border-amber-200">{dish.badge}</span>
                    ) : (
                      <span className="text-gray-300 text-xs">—</span>
                    )}
                  </td>
                  <td className="px-5 py-3.5">
                    <button
                      onClick={() => toggleAvailable(dish)}
                      disabled={saving === dish.key}
                      className={`flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors ${
                        dish.available
                          ? 'bg-green-50 text-green-700 hover:bg-green-100'
                          : 'bg-red-50 text-red-600 hover:bg-red-100'
                      }`}
                    >
                      {saving === dish.key ? (
                        <span className="w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
                      ) : (
                        <span className={`w-2 h-2 rounded-full ${dish.available ? 'bg-green-500' : 'bg-red-400'}`} />
                      )}
                      {dish.available ? 'Available' : 'Unavailable'}
                    </button>
                  </td>
                  <td className="px-5 py-3.5">
                    <button
                      onClick={() => openEdit(dish)}
                      className="text-xs px-3 py-1.5 rounded-lg bg-cream border border-cream-border text-gray-700 hover:bg-cream-border transition-colors font-semibold"
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center text-gray-400 text-sm">
                    No dishes found
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
          Showing {filtered.length} dishes
        </div>
      </div>

      {/* Edit modal */}
      {editItem && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
            <div className="px-6 py-5 border-b border-cream-border flex items-center justify-between">
              <h2 className="font-display font-bold text-xl text-maroon-deep">Edit Dish</h2>
              <button onClick={() => setEditItem(null)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
            </div>
            <form onSubmit={handleEditSave} className="p-6 space-y-4">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Name</label>
                <input className="input" value={editForm.title} onChange={e => setEditForm({ ...editForm, title: e.target.value })} required />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">Subtitle</label>
                <input className="input" value={editForm.subtitle} onChange={e => setEditForm({ ...editForm, subtitle: e.target.value })} />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Price</label>
                  <input className="input" value={editForm.price} onChange={e => setEditForm({ ...editForm, price: e.target.value })} placeholder="₹70" required />
                </div>
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Badge</label>
                  <input className="input" value={editForm.badge} onChange={e => setEditForm({ ...editForm, badge: e.target.value })} placeholder="Bestseller" />
                </div>
              </div>
              <div className="flex items-center gap-3 pt-1">
                <input
                  type="checkbox"
                  id="edit-avail"
                  checked={editForm.available}
                  onChange={e => setEditForm({ ...editForm, available: e.target.checked })}
                  className="w-4 h-4 accent-maroon"
                />
                <label htmlFor="edit-avail" className="text-sm font-semibold text-gray-700">Available to order</label>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEditItem(null)} className="btn-ghost flex-1">Cancel</button>
                <button type="submit" disabled={saving} className="btn-primary flex-1">
                  {saving ? 'Saving…' : 'Save Changes'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
