import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot, doc, updateDoc } from 'firebase/firestore'
import { db } from '../firebase'
import { format } from 'date-fns'

function fmtInr(v) {
  const s = Math.round(v || 0).toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}

function readTotal(m) {
  return m.totalRupees ?? m.total ?? m.amount ?? 0
}

function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

const STATUS_COLOR = {
  placed: 'bg-amber-100 text-amber-800',
  new: 'bg-amber-100 text-amber-800',
  preparing: 'bg-blue-100 text-blue-800',
  accepted: 'bg-blue-100 text-blue-800',
  ready: 'bg-purple-100 text-purple-800',
  delivered: 'bg-green-100 text-green-800',
  completed: 'bg-green-100 text-green-800',
  cancelled: 'bg-gray-100 text-gray-500',
}

const TABS = ['All', 'New', 'Preparing', 'Ready', 'Delivered', 'Cancelled']

const NEXT_STATUSES = {
  placed: ['preparing', 'cancelled'],
  new: ['preparing', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['delivered'],
  delivered: [],
  cancelled: [],
}

export default function Orders() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab] = useState('All')
  const [search, setSearch] = useState('')
  const [expanded, setExpanded] = useState(null)
  const [updating, setUpdating] = useState(null)

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(300))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  function matchesTab(o) {
    if (tab === 'All') return true
    const s = (o.status || '').toLowerCase()
    if (tab === 'New') return s === 'placed' || s === 'new' || s === ''
    if (tab === 'Preparing') return s === 'preparing' || s === 'accepted'
    if (tab === 'Ready') return s === 'ready'
    if (tab === 'Delivered') return s === 'delivered' || s === 'completed'
    if (tab === 'Cancelled') return s === 'cancelled'
    return true
  }

  const filtered = orders
    .filter(matchesTab)
    .filter(o => {
      if (!search) return true
      const q = search.toLowerCase()
      return o.id.toLowerCase().includes(q) ||
        (o.uid || '').toLowerCase().includes(q) ||
        (o.customerName || '').toLowerCase().includes(q)
    })

  function countTab(t) {
    return orders.filter(o => {
      if (t === 'All') return true
      const s = (o.status || '').toLowerCase()
      if (t === 'New') return s === 'placed' || s === 'new' || s === ''
      if (t === 'Preparing') return s === 'preparing' || s === 'accepted'
      if (t === 'Ready') return s === 'ready'
      if (t === 'Delivered') return s === 'delivered' || s === 'completed'
      if (t === 'Cancelled') return s === 'cancelled'
      return false
    }).length
  }

  async function setStatus(orderId, status) {
    setUpdating(orderId)
    try {
      await updateDoc(doc(db, 'orders', orderId), { status })
    } finally {
      setUpdating(null)
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
          <h1 className="page-title">Orders</h1>
          <p className="page-subtitle">Manage and update all customer orders</p>
        </div>
        <input
          className="input max-w-xs"
          placeholder="Search by Order ID…"
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
      </div>

      {/* Tabs */}
      <div className="flex gap-2 flex-wrap">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 rounded-xl text-sm font-semibold transition-all ${
              tab === t
                ? 'bg-maroon text-white shadow-sm'
                : 'bg-white border border-cream-border text-gray-600 hover:bg-cream'
            }`}
          >
            {t}
            {t !== 'All' && (
              <span className={`ml-1.5 text-xs px-1.5 py-0.5 rounded-full ${
                tab === t ? 'bg-white/20 text-white' : 'bg-cream text-gray-500'
              }`}>
                {countTab(t)}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="section-card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-cream/60 border-b border-cream-border">
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Order ID</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Items</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Payment</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(o => {
                const st = (o.status || 'placed').toLowerCase()
                const t = readCreatedAt(o)
                const isExp = expanded === o.id
                const nextSt = NEXT_STATUSES[st] || []

                return (
                  <>
                    <tr
                      key={o.id}
                      className="table-row cursor-pointer"
                      onClick={() => setExpanded(isExp ? null : o.id)}
                    >
                      <td className="px-5 py-3.5 font-mono font-bold text-xs text-gray-700">
                        #{o.id.slice(0, 10)}
                      </td>
                      <td className="px-5 py-3.5 text-gray-700">
                        {Array.isArray(o.items) ? (
                          <span className="truncate max-w-[160px] block">
                            {o.items.map(i => i.name).join(', ')}
                          </span>
                        ) : '—'}
                      </td>
                      <td className="px-5 py-3.5 font-bold text-gray-900">{fmtInr(readTotal(o))}</td>
                      <td className="px-5 py-3.5 text-gray-500 text-xs capitalize">
                        {(o.payment_mode || 'cod').replace(/_/g, ' ')}
                      </td>
                      <td className="px-5 py-3.5 text-gray-500 text-xs whitespace-nowrap">
                        {t ? format(t, 'd MMM, h:mm a') : '—'}
                      </td>
                      <td className="px-5 py-3.5">
                        <span className={`badge ${STATUS_COLOR[st] || 'bg-gray-100 text-gray-500'}`}>
                          {st.charAt(0).toUpperCase() + st.slice(1)}
                        </span>
                      </td>
                      <td className="px-5 py-3.5">
                        <div className="flex gap-2 flex-wrap" onClick={e => e.stopPropagation()}>
                          {nextSt.map(ns => (
                            <button
                              key={ns}
                              disabled={updating === o.id}
                              onClick={() => setStatus(o.id, ns)}
                              className={`text-xs px-3 py-1.5 rounded-lg font-semibold transition-colors ${
                                ns === 'cancelled'
                                  ? 'bg-red-50 text-red-700 hover:bg-red-100'
                                  : 'bg-maroon text-white hover:bg-maroon-deep'
                              }`}
                            >
                              {updating === o.id ? '…' : ns.charAt(0).toUpperCase() + ns.slice(1)}
                            </button>
                          ))}
                          {nextSt.length === 0 && <span className="text-xs text-gray-400">—</span>}
                        </div>
                      </td>
                    </tr>

                    {/* Expanded detail row */}
                    {isExp && (
                      <tr key={`${o.id}-exp`} className="bg-cream/40">
                        <td colSpan={7} className="px-5 py-4">
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                            <div>
                              <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Order Items</p>
                              <div className="space-y-1.5">
                                {Array.isArray(o.items) ? o.items.map((item, i) => (
                                  <div key={i} className="flex justify-between text-sm">
                                    <span className="text-gray-700">{item.name} {item.subtitle ? `(${item.subtitle})` : ''} × {item.qty || 1}</span>
                                    <span className="font-semibold text-gray-900">₹{(item.priceRupees || 0) * (item.qty || 1)}</span>
                                  </div>
                                )) : <p className="text-gray-400 text-sm">No items</p>}
                              </div>
                            </div>
                            <div>
                              <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Delivery Details</p>
                              <p className="text-sm text-gray-700">{o.deliveryAddress || o.address || '—'}</p>
                              {o.scheduleLabel && (
                                <p className="text-sm text-gray-500 mt-1">📅 {o.scheduleLabel}</p>
                              )}
                              {o.uid && (
                                <p className="text-xs text-gray-400 mt-2 font-mono">UID: {o.uid}</p>
                              )}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-6 py-12 text-center text-gray-400 text-sm">
                    No orders found
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
          Showing {filtered.length} of {orders.length} orders
        </div>
      </div>
    </div>
  )
}
