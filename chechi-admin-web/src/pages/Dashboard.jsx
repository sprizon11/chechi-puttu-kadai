import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { format, subDays, startOfDay, startOfMonth, eachDayOfInterval } from 'date-fns'
import { useNavigate } from 'react-router-dom'

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
  const [orders, setOrders]   = useState([])
  const [loading, setLoading] = useState(true)
  const [chartRange, setChartRange] = useState('This Week') // 'This Week' | 'This Month'
  const navigate = useNavigate()

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(500))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  const now = new Date()

  // ── All-time stats (matching Flutter dashboard) ────────────────────────────
  const totalOrders   = orders.length
  const totalRevenue  = orders.reduce((s, o) => s + readTotal(o), 0)
  const uniqueUids    = new Set(orders.map(o => (o.uid || '').trim()).filter(Boolean)).size
  const activePipeline = orders.filter(o => {
    const s = (o.status || '').toLowerCase()
    return s !== 'delivered' && s !== 'completed' && s !== 'cancelled'
  }).length

  // ── Today snapshot ─────────────────────────────────────────────────────────
  const todayStart = startOfDay(now)
  const todayOrders = orders.filter(o => {
    const t = readCreatedAt(o)
    return t && startOfDay(t).getTime() === todayStart.getTime()
  })
  const todayRevenue = todayOrders.reduce((s, o) => s + readTotal(o), 0)

  // ── Order Overview chart ───────────────────────────────────────────────────
  const chartStart = chartRange === 'This Week'
    ? startOfDay(subDays(now, 6))
    : startOfMonth(now)

  const chartDays = eachDayOfInterval({ start: chartStart, end: startOfDay(now) })
  const chartData = chartDays.map(day => {
    const dayOrders = orders.filter(o => {
      const t = readCreatedAt(o)
      return t && startOfDay(t).getTime() === day.getTime()
    })
    return {
      day: chartRange === 'This Week' ? format(day, 'EEE') : format(day, 'd'),
      revenue: dayOrders.reduce((s, o) => s + readTotal(o), 0),
      count: dayOrders.length,
    }
  })

  // ── Peak dishes (all-time) ─────────────────────────────────────────────────
  const dishCounts = {}
  orders.forEach(o => {
    if (!Array.isArray(o.items)) return
    o.items.forEach(item => {
      const name = (item.name || '').trim()
      if (!name) return
      dishCounts[name] = (dishCounts[name] || 0) + (Number(item.qty) || 1)
    })
  })
  const topDishes = Object.entries(dishCounts).sort((a, b) => b[1] - a[1]).slice(0, 6)
  const maxDish = topDishes[0]?.[1] || 1

  // ── Recent orders ─────────────────────────────────────────────────────────
  const recent = orders.slice(0, 8)

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  return (
    <div className="space-y-6">
      {/* Welcome */}
      <div>
        <h1 className="font-display font-bold text-3xl text-maroon-deep leading-tight">Welcome, Admin</h1>
        <p className="text-sm text-gray-500 mt-1">Here's what's happening with your business today.</p>
        {todayOrders.length > 0 && (
          <p className="text-xs text-gray-400 mt-0.5">
            Today: <span className="font-semibold text-gray-600">{todayOrders.length} orders</span> · <span className="font-semibold text-gray-600">{fmtInr(todayRevenue)}</span> revenue
          </p>
        )}
      </div>

      {/* Stat cards — all-time, matching Flutter */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: 'Orders', value: totalOrders,          sub: 'Total all-time',              icon: '🧾', color: 'bg-orange-50' },
          { label: 'Revenue', value: fmtInr(totalRevenue), sub: 'From all orders',             icon: '💰', color: 'bg-green-50'  },
          { label: 'Customers', value: uniqueUids,         sub: 'Unique customers',            icon: '👥', color: 'bg-amber-50'  },
          { label: 'Active Pipeline', value: activePipeline, sub: 'Not delivered / cancelled', icon: '📦', color: 'bg-purple-50' },
        ].map(c => (
          <div key={c.label} className="stat-card flex items-start gap-4">
            <div className={`w-12 h-12 rounded-xl flex items-center justify-center text-xl shrink-0 ${c.color}`}>{c.icon}</div>
            <div className="min-w-0">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{c.label}</p>
              <p className="text-2xl font-bold text-gray-900 mt-0.5">{c.value}</p>
              <p className="text-xs text-gray-400 mt-0.5">{c.sub}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Quick Actions — matching Flutter */}
      <div>
        <h2 className="font-display font-bold text-lg text-maroon-deep mb-3">Quick Actions</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[
            { label: 'Manage Menu',  icon: '🍽️', path: '/menu',      color: 'bg-orange-50 border-orange-100 hover:bg-orange-100' },
            { label: 'View Orders',  icon: '🧾', path: '/orders',    color: 'bg-blue-50 border-blue-100 hover:bg-blue-100'       },
            { label: 'Customers',    icon: '👥', path: '/customers', color: 'bg-amber-50 border-amber-100 hover:bg-amber-100'    },
            { label: 'Reports',      icon: '📊', path: '/reports',   color: 'bg-purple-50 border-purple-100 hover:bg-purple-100' },
          ].map(a => (
            <button key={a.label} onClick={() => navigate(a.path)}
              className={`flex items-center gap-3 p-4 rounded-xl border text-left font-semibold text-sm text-gray-700 transition-colors ${a.color}`}>
              <span className="text-2xl">{a.icon}</span>
              {a.label}
            </button>
          ))}
        </div>
      </div>

      {/* Order Overview chart + Peak Dishes */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Order Overview */}
        <div className="section-card lg:col-span-2 p-6">
          <div className="flex items-center justify-between mb-1">
            <h2 className="font-display font-bold text-lg text-maroon-deep">Order Overview</h2>
            <div className="flex gap-1 bg-cream rounded-xl p-1">
              {['This Week', 'This Month'].map(r => (
                <button key={r} onClick={() => setChartRange(r)}
                  className={`text-xs font-semibold px-3 py-1.5 rounded-lg transition-all ${chartRange === r ? 'bg-maroon text-white shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
                  {r}
                </button>
              ))}
            </div>
          </div>
          <p className="text-xs text-gray-400 mb-4">Revenue ({chartRange.toLowerCase()})</p>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={chartData}>
              <defs>
                <linearGradient id="dashRevGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#7C1D1B" stopOpacity={0.25} />
                  <stop offset="95%" stopColor="#7C1D1B" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#E4D7C7" vertical={false} />
              <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false}
                interval={chartRange === 'This Month' ? 4 : 0} />
              <YAxis tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false} tickFormatter={v => '₹' + v} width={55} />
              <Tooltip
                formatter={(v, name) => [name === 'revenue' ? fmtInr(v) : v, name === 'revenue' ? 'Revenue' : 'Orders']}
                contentStyle={{ borderRadius: 12, border: '1px solid #E4D7C7', fontSize: 13 }}
              />
              <Area type="monotone" dataKey="revenue" stroke="#7C1D1B" strokeWidth={2.5} fill="url(#dashRevGrad)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Peak Dishes */}
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
                    <span className={`text-xs font-bold w-5 shrink-0 ${rankColors[i]}`}>#{i + 1}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-gray-800 truncate">{name}</p>
                      <div className="mt-1 h-1.5 bg-cream-border rounded-full overflow-hidden">
                        <div className="h-full rounded-full bg-maroon" style={{ width: `${(qty / maxDish) * 100}%`, opacity: 0.82 - i * 0.07 }} />
                      </div>
                    </div>
                    <span className="text-xs font-bold text-gray-600 w-6 text-right">{qty}</span>
                  </div>
                )
              })}
            </div>
          )}
          <button onClick={() => navigate('/reports')} className="mt-4 text-xs font-semibold text-brand-orange hover:underline">
            View full report →
          </button>
        </div>
      </div>

      {/* Recent Orders */}
      <div className="section-card">
        <div className="px-6 py-4 border-b border-cream-border flex items-center justify-between">
          <h2 className="font-display font-bold text-lg text-maroon-deep">Recent Orders</h2>
          <button onClick={() => navigate('/orders')} className="text-sm font-semibold text-brand-orange hover:underline">View all →</button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-cream/60">
                {['Order ID', 'Items', 'Amount', 'Time', 'Status'].map(h => (
                  <th key={h} className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {recent.map(o => {
                const st = (o.status || 'placed').toLowerCase()
                const t  = readCreatedAt(o)
                return (
                  <tr key={o.id} className="table-row cursor-pointer" onClick={() => navigate('/orders')}>
                    <td className="px-6 py-3 font-mono font-bold text-xs text-gray-700">#{o.id.slice(0, 8)}</td>
                    <td className="px-6 py-3 text-gray-700">
                      {Array.isArray(o.items)
                        ? o.items.slice(0, 2).map(i => i.name).join(', ') + (o.items.length > 2 ? ` +${o.items.length - 2}` : '')
                        : '—'}
                    </td>
                    <td className="px-6 py-3 font-bold text-gray-900">{fmtInr(readTotal(o))}</td>
                    <td className="px-6 py-3 text-gray-500 text-xs">{t ? format(t, 'd MMM, h:mm a') : '—'}</td>
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
