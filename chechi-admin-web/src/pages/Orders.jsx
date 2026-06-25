import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot, doc, updateDoc } from 'firebase/firestore'
import { db } from '../firebase'
import { formatDistanceToNow, format } from 'date-fns'

function fmtInr(v) {
  const n = Math.round(v || 0)
  const s = n.toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest  = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}

function readTotal(m) { return m.total_rupees ?? m.totalRupees ?? m.total ?? m.amount ?? 0 }

function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

function relTime(t) {
  if (!t) return ''
  return formatDistanceToNow(t, { addSuffix: true })
}

function orderRef(id) {
  const tail = id.length >= 4 ? id.slice(-4).toUpperCase() : id.toUpperCase()
  return `#ORD${tail}`
}

function payLabel(raw) {
  const r = (raw || '').toLowerCase().replace(/_/g, ' ').trim()
  if (!r || r === 'cod') return 'Cash on Delivery'
  return r.replace(/\b\w/g, c => c.toUpperCase())
}

const TABS = [
  { label: 'New Orders',  key: 'new',       statuses: ['placed','new',''] },
  { label: 'Preparing',   key: 'preparing',  statuses: ['preparing','accepted'] },
  { label: 'Ready',       key: 'ready',      statuses: ['ready'] },
  { label: 'Completed',   key: 'completed',  statuses: ['delivered','completed'] },
  { label: 'Cancelled',   key: 'cancelled',  statuses: ['cancelled'] },
]

const STATUS_CHIP = {
  new:       { label: 'NEW',       bg: 'bg-amber-500',  text: 'text-white' },
  preparing: { label: 'PREPARING', bg: 'bg-blue-600',   text: 'text-white' },
  ready:     { label: 'READY',     bg: 'bg-green-600',  text: 'text-white' },
  completed: { label: 'COMPLETED', bg: 'bg-gray-400',   text: 'text-white' },
  cancelled: { label: 'CANCELLED', bg: 'bg-gray-300',   text: 'text-gray-600' },
}

function getTabKey(status) {
  const s = (status || '').toLowerCase()
  if (s === 'placed' || s === 'new' || s === '') return 'new'
  if (s === 'preparing' || s === 'accepted') return 'preparing'
  if (s === 'ready') return 'ready'
  if (s === 'delivered' || s === 'completed') return 'completed'
  if (s === 'cancelled') return 'cancelled'
  return 'new'
}

const NEXT_ACTIONS = {
  new:       [{ label: 'Accept Order',   status: 'preparing', style: 'primary' }, { label: 'Reject', status: 'cancelled', style: 'danger' }],
  preparing: [{ label: 'Mark Ready',     status: 'ready',     style: 'primary' }, { label: 'Cancel', status: 'cancelled', style: 'danger' }],
  ready:     [{ label: 'Mark Delivered', status: 'delivered', style: 'primary' }],
  completed: [],
  cancelled: [],
}

function OrderCard({ order, users, onUpdate, updating }) {
  const tabKey = getTabKey(order.status)
  const chip   = STATUS_CHIP[tabKey] || STATUS_CHIP.new
  const t      = readCreatedAt(order)
  const total  = readTotal(order)
  const items  = Array.isArray(order.items) ? order.items : []
  const actions = NEXT_ACTIONS[tabKey] || []

  // Resolve customer name/phone from users collection
  const userProfile = users.find(u => u.id === order.uid)
  const rawName  = order.customer_name || userProfile?.displayName || userProfile?.name || ''
  const custName = (rawName && rawName.toLowerCase() !== 'customer') ? rawName : (() => {
    const phone = userProfile?.mobile || userProfile?.authPhone || order.customer_mobile || ''
    const digits = phone.replace(/\D/g, '')
    if (digits.length >= 4) return `Customer ${digits.slice(-4)}`
    const tail = order.uid?.slice(-6) || ''
    return tail ? `Customer · …${tail.toUpperCase()}` : 'Customer'
  })()
  const custPhone = userProfile?.mobile || userProfile?.authPhone || order.customer_mobile || '—'
  const delivery  = (order.delivery_line || order.deliveryAddress || order.address || '').trim()
  const schedLine = (order.schedule_line || order.scheduleLabel || '').trim()

  return (
    <div className="bg-white rounded-2xl border border-cream-border shadow-sm overflow-hidden flex flex-col card-hover">

      {/* ── Header ── */}
      <div className="px-4 pt-4 pb-3 border-b border-cream-border">
        <div className="flex items-center justify-between gap-2 mb-2">
          <span className={`text-[10px] font-black tracking-widest px-2.5 py-1 rounded-lg ${chip.bg} ${chip.text}`}>
            {chip.label}
          </span>
          {t && (
            <div className="flex items-center gap-1 text-amber-600">
              <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span className="text-xs font-semibold">{relTime(t)}</span>
            </div>
          )}
        </div>
        <p className="font-display font-bold text-xl text-maroon-deep leading-tight">{orderRef(order.id)}</p>
        {t && <p className="text-xs text-gray-400 mt-0.5">{format(t, 'd MMM yyyy, h:mm a')}</p>}
      </div>

      {/* ── Customer & delivery ── */}
      <div className="px-4 py-3 space-y-2 border-b border-cream-border">
        <div className="flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
          </svg>
          <span className="text-sm font-semibold text-gray-800 truncate">{custName}</span>
        </div>
        <div className="flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
          </svg>
          <span className="text-sm text-gray-600 font-mono">{custPhone}</span>
        </div>
        {delivery && (
          <div className="flex items-start gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <span className="text-sm text-gray-600 leading-snug">{delivery}</span>
          </div>
        )}
        {schedLine && (
          <div className="flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-amber-500 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span className="text-sm text-amber-700 font-semibold">{schedLine}</span>
          </div>
        )}
      </div>

      {/* ── Items ── */}
      <div className="px-4 py-3 flex-1">
        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2">Items ({items.length})</p>
        <div className="space-y-1.5">
          {items.map((item, i) => {
            const qty  = Number(item.qty) || 1
            const unit = item.priceRupees ?? item.price ?? 0
            const line = unit * qty
            return (
              <div key={i} className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-1.5 min-w-0">
                  <span className="text-gray-400 mt-0.5 text-sm leading-none">•</span>
                  <p className="text-sm text-gray-800">
                    <span className="font-semibold">{item.name}</span>
                    <span className="text-gray-500"> &times; {qty}</span>
                  </p>
                </div>
                {unit > 0 && <span className="text-sm font-semibold text-gray-700 shrink-0">{fmtInr(line)}</span>}
              </div>
            )
          })}
          {items.length === 0 && <p className="text-sm text-gray-400">No items recorded</p>}
        </div>
      </div>

      {/* ── Footer: total + payment + actions ── */}
      <div className="px-4 pt-2 pb-4 border-t border-cream-border mt-auto">
        <div className="flex items-center justify-between mb-3 pt-2">
          <div className="flex items-center gap-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
            </svg>
            <span className="text-xs text-gray-500">{payLabel(order.payment_mode)}</span>
          </div>
          <span className="text-lg font-bold text-maroon-deep">{fmtInr(total)}</span>
        </div>

        {actions.length > 0 && (
          <div className="flex gap-2">
            {actions.map(a => (
              <button
                key={a.status}
                disabled={updating === order.id}
                onClick={() => onUpdate(order.id, a.status)}
                className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-colors ${
                  a.style === 'primary'
                    ? 'bg-maroon text-white hover:bg-maroon-deep'
                    : 'bg-red-50 border border-red-200 text-red-700 hover:bg-red-100'
                } disabled:opacity-50`}
              >
                {updating === order.id ? (
                  <span className="flex items-center justify-center gap-1.5">
                    <span className="w-3.5 h-3.5 border-2 border-current border-t-transparent rounded-full animate-spin" />
                    Updating…
                  </span>
                ) : a.label}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export default function Orders() {
  const [orders, setOrders]   = useState([])
  const [users, setUsers]     = useState([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab]         = useState('new')
  const [search, setSearch]   = useState('')
  const [sort, setSort]       = useState('newest')
  const [updating, setUpdating] = useState(null)

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(400))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  useEffect(() => {
    const q = query(collection(db, 'users'), limit(500))
    return onSnapshot(q, snap => setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() }))))
  }, [])

  function countTab(key) {
    return orders.filter(o => getTabKey(o.status) === key).length
  }

  const filtered = orders
    .filter(o => getTabKey(o.status) === tab)
    .filter(o => {
      if (!search) return true
      const q = search.toLowerCase()
      return o.id.toLowerCase().includes(q)
        || (o.customer_name || '').toLowerCase().includes(q)
        || (o.delivery_line || '').toLowerCase().includes(q)
    })
    .sort((a, b) => {
      const ta = readCreatedAt(a)?.getTime() || 0
      const tb = readCreatedAt(b)?.getTime() || 0
      return sort === 'newest' ? tb - ta : ta - tb
    })

  async function handleUpdate(orderId, status) {
    setUpdating(orderId)
    try {
      await updateDoc(doc(db, 'orders', orderId), { status })
    } finally {
      setUpdating(null)
    }
  }

  const hintText = {
    new:       'Accept an order to start preparing it. Reject only if you cannot fulfil it.',
    preparing: 'Tap Mark Ready when the food is packed and ready for pickup or delivery.',
    ready:     'Tap Mark Delivered once the customer has received the order.',
    completed: 'These orders are completed.',
    cancelled: 'These orders were cancelled.',
  }

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  const newCount = countTab('new')

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <h1 className="page-title">Orders</h1>
            {newCount > 0 && (
              <span className="bg-red-500 text-white text-xs font-black rounded-full px-2 py-0.5">
                {newCount} new
              </span>
            )}
          </div>
          <p className="page-subtitle">Manage and receive customer orders</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <input className="input max-w-[200px]" placeholder="Search orders..." value={search} onChange={e => setSearch(e.target.value)} />
          <select className="input max-w-[130px]" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="newest">Newest first</option>
            <option value="oldest">Oldest first</option>
          </select>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 flex-wrap">
        {TABS.map(t => {
          const count = countTab(t.key)
          const isActive = tab === t.key
          return (
            <button key={t.key} onClick={() => setTab(t.key)}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold transition-all ${
                isActive ? 'bg-maroon text-white shadow-sm' : 'bg-white border border-cream-border text-gray-600 hover:bg-cream'
              }`}>
              {t.label}
              {count > 0 && (
                <span className={`text-xs px-1.5 py-0.5 rounded-full font-bold ${
                  isActive
                    ? 'bg-white/20 text-white'
                    : t.key === 'new' ? 'bg-red-100 text-red-700' : 'bg-cream text-gray-500'
                }`}>
                  {count}
                </span>
              )}
            </button>
          )
        })}
      </div>

      {/* Hint */}
      <div className="flex items-center gap-2 text-xs text-gray-400">
        <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span>{hintText[tab]}</span>
      </div>

      {/* Cards grid */}
      {filtered.length === 0 ? (
        <div className="section-card flex flex-col items-center justify-center py-20 gap-3 text-gray-400">
          <svg xmlns="http://www.w3.org/2000/svg" className="w-14 h-14 opacity-20" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
          <p className="font-semibold text-base">No {TABS.find(t => t.key === tab)?.label.toLowerCase()} found</p>
          {search && <p className="text-sm">Try clearing the search</p>}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
            {filtered.map(o => (
              <OrderCard
                key={o.id}
                order={o}
                users={users}
                onUpdate={handleUpdate}
                updating={updating}
              />
            ))}
          </div>
          <p className="text-xs text-center text-gray-400 pb-2">
            Showing {filtered.length} of {orders.length} orders
          </p>
        </>
      )}
    </div>
  )
}
