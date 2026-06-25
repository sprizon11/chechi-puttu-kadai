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

                    {/* Expanded detail panel */}
                    {isExp && (
                      <tr key={`${o.id}-exp`}>
                        <td colSpan={7} className="px-4 pb-3 pt-0 bg-cream/30">
                          <div className="rounded-2xl border border-cream-border bg-white overflow-hidden shadow-sm">
                            <div className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 sm:divide-x divide-cream-border">

                              {/* Items */}
                              <div className="p-4">
                                <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-3">Order Items</p>
                                <div className="space-y-2">
                                  {Array.isArray(o.items) && o.items.length > 0 ? o.items.map((item, i) => {
                                    const unitPrice = item.priceRupees ?? item.price ?? 0
                                    const qty = item.qty || 1
                                    return (
                                      <div key={i} className="flex items-start justify-between gap-3">
                                        <div className="flex items-start gap-2 min-w-0">
                                          <span className="mt-0.5 w-5 h-5 rounded-full bg-maroon/10 text-maroon text-[10px] font-bold flex items-center justify-center shrink-0">{qty}</span>
                                          <div className="min-w-0">
                                            <p className="text-sm font-semibold text-gray-800 leading-tight">{item.name}</p>
                                            {item.subtitle && <p className="text-xs text-gray-400 truncate">{item.subtitle}</p>}
                                          </div>
                                        </div>
                                        {unitPrice > 0 && (
                                          <p className="text-sm font-bold text-gray-900 shrink-0">₹{unitPrice * qty}</p>
                                        )}
                                      </div>
                                    )
                                  }) : <p className="text-sm text-gray-400">No items recorded</p>}
                                </div>
                                {/* Total */}
                                {readTotal(o) > 0 && (
                                  <div className="mt-3 pt-3 border-t border-cream-border flex justify-between">
                                    <span className="text-sm font-bold text-gray-700">Total</span>
                                    <span className="text-sm font-bold text-maroon-deep">{fmtInr(readTotal(o))}</span>
                                  </div>
                                )}
                              </div>

                              {/* Delivery & payment */}
                              <div className="p-4 space-y-3">
                                <p className="text-xs font-bold text-gray-400 uppercase tracking-wide">Delivery & Payment</p>
                                <div className="space-y-2 text-sm">
                                  {(o.delivery_line || o.deliveryAddress || o.address) && (
                                    <div className="flex items-start gap-2">
                                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 mt-0.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                      </svg>
                                      <p className="text-gray-700 leading-snug">{o.delivery_line || o.deliveryAddress || o.address}</p>
                                    </div>
                                  )}
                                  {o.payment_mode && (
                                    <div className="flex items-center gap-2">
                                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                                      </svg>
                                      <p className="text-gray-700 capitalize">{o.payment_mode.replace(/_/g, ' ')}</p>
                                    </div>
                                  )}
                                  {o.delivery_type && (
                                    <div className="flex items-center gap-2">
                                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
                                      </svg>
                                      <p className="text-gray-700 capitalize">{o.delivery_type}</p>
                                    </div>
                                  )}
                                  {o.scheduleLabel && (
                                    <div className="flex items-center gap-2">
                                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                      </svg>
                                      <p className="text-gray-700">{o.scheduleLabel}</p>
                                    </div>
                                  )}
                                  {o.note && (
                                    <div className="flex items-start gap-2">
                                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 mt-0.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
                                      </svg>
                                      <p className="text-gray-700 italic">"{o.note}"</p>
                                    </div>
                                  )}
                                </div>

                                {/* Action buttons */}
                                {nextSt.length > 0 && (
                                  <div className="pt-2 flex gap-2 flex-wrap" onClick={e => e.stopPropagation()}>
                                    {nextSt.map(ns => (
                                      <button
                                        key={ns}
                                        disabled={updating === o.id}
                                        onClick={() => setStatus(o.id, ns)}
                                        className={`flex-1 py-2 rounded-xl text-sm font-bold transition-colors ${
                                          ns === 'cancelled'
                                            ? 'bg-red-50 border border-red-200 text-red-700 hover:bg-red-100'
                                            : 'bg-maroon text-white hover:bg-maroon-deep'
                                        }`}
                                      >
                                        {updating === o.id ? '…' : `Mark ${ns.charAt(0).toUpperCase() + ns.slice(1)}`}
                                      </button>
                                    ))}
                                  </div>
                                )}
                              </div>
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
