import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { format, subDays, startOfDay } from 'date-fns'

function fmtInr(v) {
  const s = Math.round(v || 0).toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}

function readTotal(m) {
  const v = m.totalRupees ?? m.total ?? m.amount ?? 0
  return typeof v === 'number' ? v : 0
}

function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

function StatCard({ label, value, sub, color, icon }) {
  return (
    <div className="stat-card flex items-start gap-4">
      <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-xl shrink-0 ${color}`}>
        {icon}
      </div>
      <div className="min-w-0">
        <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{label}</p>
        <p className="text-2xl font-bold text-gray-900 mt-0.5">{value}</p>
        {sub && <p className="text-xs text-gray-400 mt-0.5">{sub}</p>}
      </div>
    </div>
  )
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

export default function Dashboard() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(500))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  // Stats
  const today = startOfDay(new Date())
  const todayOrders = orders.filter(o => {
    const t = readCreatedAt(o)
    return t && startOfDay(t).getTime() === today.getTime()
  })
  const todayRevenue = todayOrders.reduce((s, o) => s + readTotal(o), 0)
  const activeOrders = orders.filter(o => {
    const s = (o.status || '').toLowerCase()
    return s === 'placed' || s === 'new' || s === 'preparing' || s === 'accepted' || s === 'ready'
  })
  const totalRevenue = orders.reduce((s, o) => s + readTotal(o), 0)

  // 7-day chart
  const chartData = Array.from({ length: 7 }, (_, i) => {
    const day = subDays(new Date(), 6 - i)
    const dayStart = startOfDay(day)
    const rev = orders
      .filter(o => {
        const t = readCreatedAt(o)
        return t && startOfDay(t).getTime() === dayStart.getTime()
      })
      .reduce((s, o) => s + readTotal(o), 0)
    return { day: format(day, 'EEE'), revenue: rev }
  })

  // Peak dishes
  const dishCounts = {}
  orders.forEach(o => {
    const items = o.items
    if (!Array.isArray(items)) return
    items.forEach(item => {
      const name = (item.name || '').trim()
      if (!name) return
      const qty = Number(item.qty) || 1
      dishCounts[name] = (dishCounts[name] || 0) + qty
    })
  })
  const topDishes = Object.entries(dishCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
  const maxDish = topDishes[0]?.[1] || 1

  // Recent orders
  const recent = orders.slice(0, 8)

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Stat cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Today's Revenue" value={fmtInr(todayRevenue)} sub={`${todayOrders.length} orders today`} icon="💰" color="bg-green-50" />
        <StatCard label="Active Orders" value={activeOrders.length} sub="In progress right now" icon="🔥" color="bg-amber-50" />
        <StatCard label="Total Orders" value={orders.length} sub="All time" icon="🧾" color="bg-blue-50" />
        <StatCard label="Total Revenue" value={fmtInr(totalRevenue)} sub="All time" icon="📈" color="bg-purple-50" />
      </div>

      {/* Chart + Peak Dishes */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Revenue chart */}
        <div className="section-card lg:col-span-2 p-6">
          <h2 className="page-title text-lg mb-1">Revenue — Last 7 Days</h2>
          <p className="page-subtitle mb-5">Daily earnings trend</p>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={chartData}>
              <defs>
                <linearGradient id="revGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#7C1D1B" stopOpacity={0.25} />
                  <stop offset="95%" stopColor="#7C1D1B" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#E4D7C7" />
              <XAxis dataKey="day" tick={{ fontSize: 12, fill: '#9CA3AF' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false} tickFormatter={v => '₹' + v} width={55} />
              <Tooltip
                formatter={v => [fmtInr(v), 'Revenue']}
                contentStyle={{ borderRadius: 12, border: '1px solid #E4D7C7', fontSize: 13 }}
              />
              <Area type="monotone" dataKey="revenue" stroke="#7C1D1B" strokeWidth={2.5} fill="url(#revGrad)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Peak dishes */}
        <div className="section-card p-6">
          <div className="flex items-center gap-2 mb-4">
            <span className="text-lg">🔥</span>
            <h2 className="font-display font-bold text-lg text-maroon-deep">Peak Dishes</h2>
          </div>
          {topDishes.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-8">No order data yet</p>
          ) : (
            <div className="space-y-3">
              {topDishes.map(([name, qty], i) => {
                const rankColors = ['text-amber-500', 'text-gray-400', 'text-amber-700', 'text-maroon', 'text-maroon', 'text-maroon']
                return (
                  <div key={name} className="flex items-center gap-3">
                    <span className={`text-xs font-bold w-5 ${rankColors[i]}`}>#{i + 1}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-gray-800 truncate">{name}</p>
                      <div className="mt-1 h-1.5 bg-cream-border rounded-full overflow-hidden">
                        <div
                          className="h-full rounded-full bg-maroon"
                          style={{ width: `${(qty / maxDish) * 100}%`, opacity: 0.8 - i * 0.08 }}
                        />
                      </div>
                    </div>
                    <span className="text-xs font-bold text-gray-600 w-6 text-right">{qty}</span>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>

      {/* Recent Orders */}
      <div className="section-card">
        <div className="px-6 py-4 border-b border-cream-border flex items-center justify-between">
          <h2 className="font-display font-bold text-lg text-maroon-deep">Recent Orders</h2>
          <a href="/orders" className="text-sm font-semibold text-brand-orange hover:underline">View all →</a>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-cream/60">
                <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Order ID</th>
                <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Items</th>
                <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
                <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Time</th>
                <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              </tr>
            </thead>
            <tbody>
              {recent.map(o => {
                const st = (o.status || 'placed').toLowerCase()
                const t = readCreatedAt(o)
                return (
                  <tr key={o.id} className="table-row">
                    <td className="px-6 py-3 font-mono font-bold text-xs text-gray-700">#{o.id.slice(0, 8)}</td>
                    <td className="px-6 py-3 text-gray-700">{Array.isArray(o.items) ? o.items.length : '—'} item(s)</td>
                    <td className="px-6 py-3 font-bold text-gray-900">{fmtInr(readTotal(o))}</td>
                    <td className="px-6 py-3 text-gray-500">{t ? format(t, 'd MMM, h:mm a') : '—'}</td>
                    <td className="px-6 py-3">
                      <span className={`badge ${STATUS_COLOR[st] || 'bg-gray-100 text-gray-500'}`}>
                        {st.charAt(0).toUpperCase() + st.slice(1)}
                      </span>
                    </td>
                  </tr>
                )
              })}
              {recent.length === 0 && (
                <tr><td colSpan={5} className="px-6 py-10 text-center text-gray-400 text-sm">No orders yet</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
