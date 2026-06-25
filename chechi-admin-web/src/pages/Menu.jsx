import { useEffect, useState } from 'react'
import { collection, onSnapshot, doc, updateDoc, addDoc, deleteDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../firebase'

export default function Menu() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editItem, setEditItem] = useState(null)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(null)

  const emptyForm = { name: '', subtitle: '', priceRupees: '', category: '', description: '', available: true, imageUrl: '' }
  const [form, setForm] = useState(emptyForm)

  useEffect(() => {
    return onSnapshot(collection(db, 'admin_public'), snap => {
      setItems(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  function openAdd() {
    setEditItem(null)
    setForm(emptyForm)
    setShowForm(true)
  }

  function openEdit(item) {
    setEditItem(item)
    setForm({
      name: item.name || '',
      subtitle: item.subtitle || '',
      priceRupees: item.priceRupees?.toString() || '',
      category: item.category || '',
      description: item.description || '',
      available: item.available !== false,
      imageUrl: item.imageUrl || '',
    })
    setShowForm(true)
  }

  async function handleSave(e) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        name: form.name.trim(),
        subtitle: form.subtitle.trim(),
        priceRupees: parseFloat(form.priceRupees) || 0,
        category: form.category.trim(),
        description: form.description.trim(),
        available: form.available,
        imageUrl: form.imageUrl.trim(),
        updatedAt: serverTimestamp(),
      }
      if (editItem) {
        await updateDoc(doc(db, 'admin_public', editItem.id), data)
      } else {
        await addDoc(collection(db, 'admin_public'), { ...data, createdAt: serverTimestamp() })
      }
      setShowForm(false)
    } finally {
      setSaving(false)
    }
  }

  async function toggleAvailable(item) {
    await updateDoc(doc(db, 'admin_public', item.id), { available: !item.available })
  }

  async function handleDelete(item) {
    if (!confirm(`Delete "${item.name}"? This cannot be undone.`)) return
    setDeleting(item.id)
    try {
      await deleteDoc(doc(db, 'admin_public', item.id))
    } finally {
      setDeleting(null)
    }
  }

  const categories = [...new Set(items.map(i => i.category).filter(Boolean))]

  const filtered = items.filter(i => {
    if (!search) return true
    return (i.name || '').toLowerCase().includes(search.toLowerCase()) ||
      (i.category || '').toLowerCase().includes(search.toLowerCase())
  })

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Menu</h1>
          <p className="page-subtitle">{items.length} items · {categories.length} categories</p>
        </div>
        <div className="flex gap-3">
          <input
            className="input max-w-xs"
            placeholder="Search menu…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
          <button onClick={openAdd} className="btn-primary whitespace-nowrap">+ Add Item</button>
        </div>
      </div>

      {/* Menu grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {filtered.map(item => (
          <div key={item.id} className="bg-white rounded-2xl border border-cream-border shadow-sm overflow-hidden">
            {item.imageUrl ? (
              <img src={item.imageUrl} alt={item.name} className="w-full h-40 object-cover" />
            ) : (
              <div className="w-full h-40 bg-cream flex items-center justify-center text-4xl">🍽️</div>
            )}
            <div className="p-4">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-bold text-gray-900 truncate">{item.name}</p>
                  {item.subtitle && <p className="text-xs text-gray-500 truncate">{item.subtitle}</p>}
                </div>
                <p className="font-bold text-maroon shrink-0">₹{item.priceRupees || 0}</p>
              </div>
              {item.category && (
                <span className="mt-2 inline-block badge bg-cream text-gray-600 border border-cream-border">
                  {item.category}
                </span>
              )}
              <div className="mt-3 flex items-center justify-between">
                {/* Available toggle */}
                <button
                  onClick={() => toggleAvailable(item)}
                  className={`flex items-center gap-2 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors ${
                    item.available !== false
                      ? 'bg-green-50 text-green-700'
                      : 'bg-red-50 text-red-700'
                  }`}
                >
                  <span className={`w-2 h-2 rounded-full ${item.available !== false ? 'bg-green-500' : 'bg-red-400'}`} />
                  {item.available !== false ? 'Available' : 'Unavailable'}
                </button>
                <div className="flex gap-1">
                  <button
                    onClick={() => openEdit(item)}
                    className="p-2 rounded-lg hover:bg-cream text-gray-500 hover:text-maroon transition-colors text-sm"
                    title="Edit"
                  >✏️</button>
                  <button
                    onClick={() => handleDelete(item)}
                    disabled={deleting === item.id}
                    className="p-2 rounded-lg hover:bg-red-50 text-gray-500 hover:text-red-600 transition-colors text-sm"
                    title="Delete"
                  >{deleting === item.id ? '…' : '🗑️'}</button>
                </div>
              </div>
            </div>
          </div>
        ))}
        {filtered.length === 0 && (
          <div className="col-span-full py-16 text-center text-gray-400">
            <p className="text-4xl mb-3">🍽️</p>
            <p className="text-sm">No menu items yet. Click "+ Add Item" to get started.</p>
          </div>
        )}
      </div>

      {/* Add/Edit Modal */}
      {showForm && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
            <div className="px-6 py-5 border-b border-cream-border flex items-center justify-between">
              <h2 className="font-display font-bold text-xl text-maroon-deep">
                {editItem ? 'Edit Menu Item' : 'Add Menu Item'}
              </h2>
              <button onClick={() => setShowForm(false)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
            </div>
            <form onSubmit={handleSave} className="p-6 space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2">
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Dish Name *</label>
                  <input className="input" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} required placeholder="e.g. Puttu" />
                </div>
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Price (₹) *</label>
                  <input className="input" type="number" min="0" step="0.5" value={form.priceRupees} onChange={e => setForm({ ...form, priceRupees: e.target.value })} required placeholder="60" />
                </div>
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Category</label>
                  <input className="input" value={form.category} onChange={e => setForm({ ...form, category: e.target.value })} placeholder="Breakfast" list="cats" />
                  <datalist id="cats">{categories.map(c => <option key={c} value={c} />)}</datalist>
                </div>
                <div className="col-span-2">
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Subtitle / Variant</label>
                  <input className="input" value={form.subtitle} onChange={e => setForm({ ...form, subtitle: e.target.value })} placeholder="With Kadala Curry" />
                </div>
                <div className="col-span-2">
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Description</label>
                  <textarea className="input resize-none" rows={2} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Short description…" />
                </div>
                <div className="col-span-2">
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">Image URL</label>
                  <input className="input" value={form.imageUrl} onChange={e => setForm({ ...form, imageUrl: e.target.value })} placeholder="https://…" />
                </div>
                <div className="col-span-2 flex items-center gap-3">
                  <input
                    type="checkbox"
                    id="avail"
                    checked={form.available}
                    onChange={e => setForm({ ...form, available: e.target.checked })}
                    className="w-4 h-4 accent-maroon"
                  />
                  <label htmlFor="avail" className="text-sm font-semibold text-gray-700">Available to order</label>
                </div>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowForm(false)} className="btn-ghost flex-1">Cancel</button>
                <button type="submit" disabled={saving} className="btn-primary flex-1">
                  {saving ? 'Saving…' : editItem ? 'Save Changes' : 'Add Item'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
