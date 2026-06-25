import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { format, subDays, startOfDay, startOfMonth, eachDayOfInterval } from 'date-fns'
import { useNavigate } from 'react-router-dom'

/* ── helpers ─────────────────────────────────────────────────────────────── */
function fmtInr(v) {
  const s = Math.round(v || 0).toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}
function readTotal(m) {
  const v = m.total_rupees ?? m.totalRupees ?? m.total ?? m.amount ?? 0
  return typeof v === 'number' ? v : 0
}
function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}
function getGreeting() {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning'
  if (h < 17) return 'Good afternoon'
  return 'Good evening'
}
function pctChange(curr, prev) {
  if (prev === 0) return curr > 0 ? 100 : 0
  return Math.round(((curr - prev) / prev) * 1000) / 10
}

const STATUS_PILL = {
  placed:    { bg: '#FEF3C7', text: '#92400E', label: 'New' },
  new:       { bg: '#FEF3C7', text: '#92400E', label: 'New' },
  preparing: { bg: '#DBEAFE', text: '#1E40AF', label: 'Preparing' },
  accepted:  { bg: '#DBEAFE', text: '#1E40AF', label: 'Preparing' },
  ready:     { bg: '#EDE9FE', text: '#5B21B6', label: 'Ready' },
  delivered: { bg: '#D1FAE5', text: '#065F46', label: 'Delivered' },
  completed: { bg: '#D1FAE5', text: '#065F46', label: 'Completed' },
  cancelled: { bg: '#F3F4F6', text: '#6B7280', label: 'Cancelled' },
}

const MEDALS = ['🥇', '🥈', '🥉']

/* ── Stat card icon (SVG-based, no emoji) ─────────────────────────────── */
const ICONS = {
  revenue: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/>
      <path d="M12 6v2M12 16v2M8.5 9.5a3.5 3.5 0 107 0c0-1.93-1.57-3.5-3.5-3.5S8.5 7.57 8.5 9.5z"/>
      <path d="M8 14.5c.83 1.2 2.24 2 3.83 2 2.21 0 4-.9 4-2s-1.79-2-4-2c-2.21 0-4-.9-4-2s1.79-2 4-2"/>
    </svg>
  ),
  orders: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2"/>
      <rect x="9" y="3" width="6" height="4" rx="1"/>
      <path d="M9 12h6M9 16h4"/>
    </svg>
  ),
  customers: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/>
      <circle cx="9" cy="7" r="4"/>
      <path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/>
    </svg>
  ),
  active: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="w-6 h-6">
      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
    </svg>
  ),
}

/* ── Chart tooltip ────────────────────────────────────────────────────── */
function ChartTip({ active, payload, label }) {
  if (!active || !payload?.length) return null
  return (
    <div style={{ background: '#fff', border: '1px solid #E4D7C7', borderRadius: 14, padding: '10px 14px', boxShadow: '0 8px 24px rgba(0,0,0,0.1)' }}>
      <p style={{ fontSize: 11, color: '#9CA3AF', fontWeight: 700, marginBottom: 2 }}>{label}</p>
      <p style={{ fontSize: 15, color: '#5D1F1A', fontWeight: 800 }}>{fmtInr(payload[0]?.value ?? 0)}</p>
    </div>
  )
}

/* ── Main ─────────────────────────────────────────────────────────────── */
export default function Dashboard() {
  const [orders, setOrders]   = useState([])
  const [loading, setLoading] = useState(true)
  const [chartRange, setChartRange] = useState('This Week')
  const navigate = useNavigate()

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(500))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  const now = new Date()

  /* week helpers */
  const thisWeekStart = startOfDay(subDays(now, 6))
  const lastWeekStart = startOfDay(subDays(now, 13))
  function inRange(o, start, end) {
    const t = readCreatedAt(o)
    return t && t >= start && (end ? t < end : true)
  }
  const thisWeekOrds  = orders.filter(o => inRange(o, thisWeekStart))
  const lastWeekOrds  = orders.filter(o => inRange(o, lastWeekStart, thisWeekStart))
  const thisWeekRev   = thisWeekOrds.reduce((s, o) => s + readTotal(o), 0)
  const lastWeekRev   = lastWeekOrds.reduce((s, o) => s + readTotal(o), 0)
  const thisWeekUsers = new Set(thisWeekOrds.map(o => o.uid).filter(Boolean)).size
  const lastWeekUsers = new Set(lastWeekOrds.map(o => o.uid).filter(Boolean)).size
  const totalRevenue  = orders.reduce((s, o) => s + readTotal(o), 0)
  const totalOrders   = orders.length
  const uniqueUids    = new Set(orders.map(o => o.uid).filter(Boolean)).size
  const activeNow     = orders.filter(o => { const s = (o.status||'').toLowerCase(); return s !== 'delivered' && s !== 'completed' && s !== 'cancelled' })
  const activeLastWk  = lastWeekOrds.filter(o => { const s = (o.status||'').toLowerCase(); return s !== 'delivered' && s !== 'completed' && s !== 'cancelled' })

  /* chart */
  const chartStart = chartRange === 'This Week' ? thisWeekStart : startOfMonth(now)
  const chartDays  = eachDayOfInterval({ start: chartStart, end: startOfDay(now) })
  function dayOrders(day) { return orders.filter(o => { const t = readCreatedAt(o); return t && startOfDay(t).getTime() === day.getTime() }) }
  const chartData  = chartDays.map(d => ({
    label: chartRange === 'This Week' ? format(d, 'd MMM') : format(d, 'd'),
    revenue: dayOrders(d).reduce((s, o) => s + readTotal(o), 0),
  }))

  /* period stats for chart footer */
  const periodOrds   = chartRange === 'This Week' ? thisWeekOrds : orders.filter(o => inRange(o, startOfMonth(now)))
  const periodRev    = periodOrds.reduce((s, o) => s + readTotal(o), 0)
  const periodAvg    = periodOrds.length > 0 ? Math.round(periodRev / periodOrds.length) : 0
  const cancelRate   = periodOrds.length > 0 ? Math.round((periodOrds.filter(o => (o.status||'').toLowerCase() === 'cancelled').length / periodOrds.length) * 100) : 0

  /* peak dishes */
  const dishCounts = {}
  orders.forEach(o => {
    if (!Array.isArray(o.items)) return
    o.items.forEach(item => {
      const name = (item.name || '').trim()
      if (!name) return
      dishCounts[name] = (dishCounts[name] || 0) + (Number(item.qty) || 1)
    })
  })
  const topDishes = Object.entries(dishCounts).sort((a, b) => b[1] - a[1]).slice(0, 5)
  const maxDish   = topDishes[0]?.[1] || 1
  const recent    = orders.slice(0, 6)

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  const STATS = [
    {
      key: 'revenue', icon: ICONS.revenue, label: 'Total Revenue',
      value: fmtInr(totalRevenue),
      pct: pctChange(thisWeekRev, lastWeekRev),
      accent: '#16a34a', light: '#f0fdf4', iconColor: '#15803d',
    },
    {
      key: 'orders', icon: ICONS.orders, label: 'Total Orders',
      value: totalOrders.toLocaleString('en-IN'),
      pct: pctChange(thisWeekOrds.length, lastWeekOrds.length),
      accent: '#ea580c', light: '#fff7ed', iconColor: '#c2410c',
    },
    {
      key: 'customers', icon: ICONS.customers, label: 'Customers',
      value: uniqueUids.toLocaleString('en-IN'),
      pct: pctChange(thisWeekUsers, lastWeekUsers),
      accent: '#2563eb', light: '#eff6ff', iconColor: '#1d4ed8',
    },
    {
      key: 'active', icon: ICONS.active, label: 'Active Orders',
      value: activeNow.length,
      pct: pctChange(activeNow.length, activeLastWk.length),
      accent: '#7c3aed', light: '#f5f3ff', iconColor: '#5b21b6',
    },
  ]

  const QUICK = [
    { label: 'Manage Menu',  sub: 'Add or update food items',          icon: '🍽️', path: '/menu',      bg: '#fff7ed', border: '#fed7aa' },
    { label: 'View Orders',  sub: 'Check incoming orders',             icon: '🧾', path: '/orders',    bg: '#eff6ff', border: '#bfdbfe' },
    { label: 'Customers',    sub: 'View and manage users',             icon: '👥', path: '/customers', bg: '#f0fdf4', border: '#bbf7d0' },
    { label: 'Reports',      sub: 'Analyze business performance',      icon: '📊', path: '/reports',   bg: '#f5f3ff', border: '#ddd6fe' },
  ]

  return (
    <div className="space-y-7">

      {/* ── Greeting ──────────────────────────────────────────────────── */}
      <div className="flex items-start justify-between gap-4 animate-fade-in-up">
        <div>
          <div className="flex items-center gap-2.5 mb-1">
            <h1 className="font-display font-bold text-3xl text-gray-900">{getGreeting()}, Admin 👋</h1>
            <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse-dot shrink-0" />
          </div>
          <p className="text-sm text-gray-500">{format(now, 'EEEE, d MMMM yyyy')}</p>
        </div>
        <button
          onClick={() => setChartRange(r => r === 'This Week' ? 'This Month' : 'This Week')}
          className="bg-white border border-cream-border rounded-xl px-3.5 py-2 flex items-center gap-2 shrink-0 shadow-sm hover:shadow-md hover:border-gray-300 transition-all"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          <span className="text-xs font-semibold text-gray-700">
            {chartRange === 'This Week'
              ? `${format(thisWeekStart, 'd MMM')} – ${format(now, 'd MMM yyyy')}`
              : `${format(startOfMonth(now), 'd MMM')} – ${format(now, 'd MMM yyyy')}`}
          </span>
          <svg xmlns="http://www.w3.org/2000/svg" className="w-3 h-3 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      {/* ── Stat cards ────────────────────────────────────────────────── */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {STATS.map((s, i) => (
          <div
            key={s.key}
            className="animate-fade-in-up card-hover rounded-2xl px-4 py-3.5"
            style={{
              animationDelay: `${80 + i * 80}ms`,
              background: '#fff',
              border: '1px solid #EDE5DA',
              boxShadow: '0 2px 10px rgba(0,0,0,0.05)',
            }}
          >
            {/* Label + icon row */}
            <div className="flex items-center justify-between mb-2.5">
              <p className="text-[11px] font-semibold text-gray-400 uppercase tracking-wide">{s.label}</p>
              <div
                className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0"
                style={{ background: s.light, color: s.iconColor }}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ width: 14, height: 14 }}>{s.icon.props.children}</svg>
              </div>
            </div>

            {/* Number */}
            <p className="text-xl font-black text-gray-900 leading-none mb-2 tabular-nums"
              style={{ letterSpacing: '-0.02em' }}>
              {s.value}
            </p>

            {/* Trend */}
            <div className="flex items-center gap-1.5">
              <span
                className="text-[10px] font-bold px-1.5 py-0.5 rounded-md"
                style={{
                  background: s.pct === 0 ? '#f3f4f6' : s.pct > 0 ? '#f0fdf4' : '#fef2f2',
                  color: s.pct === 0 ? '#6b7280' : s.pct > 0 ? '#15803d' : '#dc2626',
                }}
              >
                {s.pct > 0 ? '↑' : s.pct < 0 ? '↓' : '—'}{Math.abs(s.pct).toFixed(1)}%
              </span>
              <span className="text-[10px] text-gray-400">vs last week</span>
            </div>
          </div>
        ))}
      </div>

      {/* ── Chart + Peak Dishes ───────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5 animate-fade-in-up" style={{ animationDelay: '400ms' }}>

        {/* Revenue chart */}
        <div className="lg:col-span-2 rounded-2xl overflow-hidden border border-cream-border card-hover"
          style={{ background: '#fff', boxShadow: '0 4px 24px rgba(0,0,0,0.06)' }}>
          <div className="px-6 pt-5 pb-1">
            <div className="flex items-start justify-between mb-5">
              <div>
                <h2 className="font-display font-bold text-xl text-gray-900">Order Overview</h2>
                <p className="text-xs text-gray-400 mt-0.5">Revenue trend for the selected period</p>
              </div>
              <div className="flex items-center gap-1.5">
                {['This Week', 'This Month'].map(r => (
                  <button key={r} onClick={() => setChartRange(r)}
                    className={`text-xs font-bold px-3.5 py-2 rounded-xl transition-all ${
                      chartRange === r
                        ? 'text-white shadow-sm'
                        : 'text-gray-500 bg-cream hover:text-gray-700'
                    }`}
                    style={chartRange === r ? { background: '#7C1D1B' } : {}}
                  >
                    {r}
                  </button>
                ))}
              </div>
            </div>

            <ResponsiveContainer width="100%" height={210}>
              <AreaChart data={chartData} margin={{ top: 4, right: 4, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="cg" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%"   stopColor="#7C1D1B" stopOpacity={0.22} />
                    <stop offset="100%" stopColor="#7C1D1B" stopOpacity={0.01} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#F0E8DC" vertical={false} />
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false}
                  interval={chartRange === 'This Month' ? 4 : 0} />
                <YAxis tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false}
                  tickFormatter={v => '₹' + v} width={55} />
                <Tooltip content={<ChartTip />} cursor={{ stroke: '#7C1D1B', strokeWidth: 1, strokeDasharray: '4 4' }} />
                <Area type="monotone" dataKey="revenue" stroke="#7C1D1B" strokeWidth={2.5}
                  fill="url(#cg)" dot={false}
                  activeDot={{ r: 5, fill: '#7C1D1B', stroke: '#fff', strokeWidth: 2.5 }} />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          {/* Chart footer stats */}
          <div className="grid grid-cols-4 border-t border-cream-border mt-1">
            {[
              { label: 'Total Revenue', value: fmtInr(periodRev),   color: '#16a34a', icon: '💰' },
              { label: 'Total Orders',  value: periodOrds.length,    color: '#ea580c', icon: '🧾' },
              { label: 'Avg. Order',    value: fmtInr(periodAvg),    color: '#2563eb', icon: '₹' },
              { label: 'Cancel Rate',   value: `${cancelRate}%`,     color: '#7c3aed', icon: '📊' },
            ].map((s, i) => (
              <div key={i} className={`px-4 py-3.5 flex items-center gap-2.5 ${i < 3 ? 'border-r border-cream-border' : ''}`}>
                <span className="text-lg shrink-0">{s.icon}</span>
                <div>
                  <p className="text-sm font-bold text-gray-900 tabular-nums leading-tight">{s.value}</p>
                  <p className="text-[10px] text-gray-400 leading-tight">{s.label}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Peak Dishes */}
        <div className="rounded-2xl border border-cream-border p-6 card-hover"
          style={{ background: '#fff', boxShadow: '0 4px 24px rgba(0,0,0,0.06)' }}>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xl animate-float inline-block">🔥</span>
            <h2 className="font-display font-bold text-xl text-gray-900">Peak Dishes</h2>
          </div>
          <p className="text-xs text-gray-400 mb-5">Your most ordered items</p>

          {topDishes.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-10">No order data yet</p>
          ) : (
            <div className="space-y-4">
              {topDishes.map(([name, qty], i) => (
                <div key={name} className="flex items-center gap-3">
                  <span className="text-xl w-7 text-center shrink-0 leading-none">
                    {i < 3 ? MEDALS[i] : <span className="text-xs font-black text-gray-300">#{i+1}</span>}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-gray-800 truncate mb-1.5">{name}</p>
                    <div className="h-1.5 rounded-full overflow-hidden" style={{ background: '#F5EEE6' }}>
                      <div className="h-full rounded-full animate-bar-grow"
                        style={{
                          width: `${(qty / maxDish) * 100}%`,
                          background: `rgba(124,29,27,${0.9 - i * 0.1})`,
                          animationDelay: `${500 + i * 80}ms`,
                        }} />
                    </div>
                  </div>
                  <span className="text-xs font-black text-gray-500 tabular-nums w-5 text-right shrink-0">{qty}</span>
                </div>
              ))}
            </div>
          )}

          <button onClick={() => navigate('/reports')}
            className="mt-5 w-full py-2.5 rounded-xl text-sm font-bold text-gray-700 flex items-center justify-center gap-1.5 transition-all hover:shadow-sm"
            style={{ background: '#FFF6ED', border: '1px solid #E4D7C7' }}>
            View full report
            <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        </div>
      </div>

      {/* ── Quick Actions ─────────────────────────────────────────────── */}
      <div className="animate-fade-in-up" style={{ animationDelay: '500ms' }}>
        <h2 className="font-display font-bold text-xl text-gray-900 mb-1">Quick Actions</h2>
        <p className="text-sm text-gray-400 mb-4">Shortcuts to manage your business</p>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {QUICK.map((a, i) => (
            <button key={a.label} onClick={() => navigate(a.path)}
              className="group rounded-2xl p-5 border text-left card-hover animate-fade-in-up flex flex-col gap-3"
              style={{
                background: a.bg, borderColor: a.border,
                boxShadow: '0 2px 12px rgba(0,0,0,0.05)',
                animationDelay: `${560 + i * 60}ms`,
              }}>
              <div className="text-3xl group-hover:scale-110 transition-transform">{a.icon}</div>
              <div>
                <p className="font-bold text-gray-900 text-sm mb-0.5">{a.label}</p>
                <p className="text-xs text-gray-500 leading-snug">{a.sub}</p>
              </div>
              <div className="flex items-center gap-1 text-xs font-bold mt-auto" style={{ color: '#7C1D1B' }}>
                Open
                <svg xmlns="http://www.w3.org/2000/svg" className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
                </svg>
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* ── Recent Orders ─────────────────────────────────────────────── */}
      <div className="rounded-2xl border border-cream-border overflow-hidden animate-fade-in-up card-hover"
        style={{ background: '#fff', boxShadow: '0 4px 24px rgba(0,0,0,0.06)', animationDelay: '620ms' }}>
        <div className="px-6 py-4 border-b border-cream-border flex items-center justify-between">
          <div>
            <h2 className="font-display font-bold text-xl text-gray-900">Recent Orders</h2>
            <p className="text-xs text-gray-400 mt-0.5">Latest transactions across all statuses</p>
          </div>
          <button onClick={() => navigate('/orders')}
            className="flex items-center gap-1.5 text-sm font-bold px-4 py-2 rounded-xl transition-all hover:shadow-sm"
            style={{ background: '#FFF6ED', color: '#7C1D1B', border: '1px solid #E4D7C7' }}>
            View all orders
            <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: '#FDFAF7', borderBottom: '1px solid #E4D7C7' }}>
                {['Order', 'Customer', 'Items', 'Amount', 'Time', 'Status'].map(h => (
                  <th key={h} className="text-left px-6 py-3 text-[10px] font-black text-gray-400 uppercase tracking-widest">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {recent.map((o, idx) => {
                const rawSt = (o.status || 'placed').toLowerCase()
                const pill  = STATUS_PILL[rawSt] || STATUS_PILL.placed
                const t     = readCreatedAt(o)
                const itemsText = Array.isArray(o.items)
                  ? o.items.slice(0, 2).map(i => i.name).join(', ') + (o.items.length > 2 ? ` +${o.items.length - 2}` : '')
                  : '—'
                const custName = (o.customer_name || '').trim()
                const custPhone = (o.customer_mobile || '').trim()
                return (
                  <tr key={o.id} className="table-row animate-slide-in-left"
                    style={{ animationDelay: `${680 + idx * 30}ms` }}
                    onClick={() => navigate('/orders')}>
                    <td className="px-6 py-4">
                      <span className="font-mono font-bold text-xs rounded-lg px-2.5 py-1.5"
                        style={{ background: 'rgba(124,29,27,0.07)', color: '#7C1D1B' }}>
                        #{o.id.slice(-6).toUpperCase()}
                      </span>
                    </td>
                    <td className="px-6 py-4">
                      {custName ? (
                        <div>
                          <p className="font-semibold text-gray-800 text-xs">{custName}</p>
                          {custPhone && <p className="text-gray-400 text-xs">{custPhone}</p>}
                        </div>
                      ) : (
                        <span className="text-gray-400 text-xs">—</span>
                      )}
                    </td>
                    <td className="px-6 py-4 text-gray-600 max-w-[160px] truncate text-xs">{itemsText}</td>
                    <td className="px-6 py-4 font-black text-gray-900 tabular-nums">{fmtInr(readTotal(o))}</td>
                    <td className="px-6 py-4 text-gray-400 text-xs whitespace-nowrap">
                      {t ? format(t, 'd MMM, h:mm a') : '—'}
                    </td>
                    <td className="px-6 py-4">
                      <span className="text-xs font-bold px-2.5 py-1 rounded-full"
                        style={{ background: pill.bg, color: pill.text }}>
                        {pill.label}
                      </span>
                    </td>
                  </tr>
                )
              })}
              {recent.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-16 text-center text-gray-400 text-sm">No orders yet</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
