import { useEffect, useState } from 'react'
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, Cell, PieChart, Pie, Legend
} from 'recharts'
import { format, subDays, startOfDay, startOfWeek, startOfMonth, eachDayOfInterval } from 'date-fns'

function fmtInr(v) {
  const s = Math.round(v || 0).toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}

function readTotal(m) { return m.totalRupees ?? m.total ?? m.amount ?? 0 }

function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

export default function Reports() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [range, setRange] = useState('30')

  useEffect(() => {
    const q = query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(1000))
    return onSnapshot(q, snap => {
      setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  const days = parseInt(range)
  const now = new Date()
  const startDate = startOfDay(subDays(now, days - 1))

  const rangeOrders = orders.filter(o => {
    const t = readCreatedAt(o)
    return t && t >= startDate
  })

  // Daily chart data
  const allDays = eachDayOfInterval({ start: startDate, end: startOfDay(now) })
  const dailyData = allDays.map(day => {
    const dayOrders = rangeOrders.filter(o => {
      const t = readCreatedAt(o)
      return t && startOfDay(t).getTime() === day.getTime()
    })
    return {
      day: days <= 14 ? format(day, 'd MMM') : format(day, 'd MMM'),
      revenue: dayOrders.reduce((s, o) => s + readTotal(o), 0),
      count: dayOrders.length,
    }
  })

  // Peak dishes
  const dishCounts = {}
  rangeOrders.forEach(o => {
    if (!Array.isArray(o.items)) return
    o.items.forEach(item => {
      const name = (item.name || '').trim()
      if (!name) return
      dishCounts[name] = (dishCounts[name] || 0) + (Number(item.qty) || 1)
    })
  })
  const topDishes = Object.entries(dishCounts).sort((a, b) => b[1] - a[1]).slice(0, 8)

  // Status breakdown
  const statusCounts = {}
  rangeOrders.forEach(o => {
    const s = (o.status || 'placed').toLowerCase()
    statusCounts[s] = (statusCounts[s] || 0) + 1
  })

  // Summary stats
  const totalRevenue = rangeOrders.reduce((s, o) => s + readTotal(o), 0)
  const avgOrderValue = rangeOrders.length > 0 ? totalRevenue / rangeOrders.length : 0
  const deliveredCount = rangeOrders.filter(o => ['delivered', 'completed'].includes((o.status || '').toLowerCase())).length
  const cancelledCount = rangeOrders.filter(o => o.status === 'cancelled').length

  // ── Payment method breakdown (mirrors Flutter's _paymentBreakdown) ──────────
  function paymentLabel(raw) {
    const r = (raw || '').toLowerCase().trim()
    if (r === 'cash_on_delivery' || r === 'cod') return 'Cash on Delivery'
    if (r === 'cashfree') return 'Cashfree (Online)'
    if (r === 'razorpay') return 'Razorpay (Online)'
    if (r === 'upi') return 'UPI'
    if (r === 'card') return 'Card'
    const title = r.replace(/_/g, ' ').trim()
    if (!title) return 'Other'
    return title.replace(/\b\w/g, c => c.toUpperCase())
  }
  const paymentMap = {}
  rangeOrders.forEach(o => {
    const key = paymentLabel(o.payment_mode || '')
    paymentMap[key] = (paymentMap[key] || 0) + readTotal(o)
  })
  const paymentData = Object.entries(paymentMap)
    .sort((a, b) => b[1] - a[1])
    .map(([name, value]) => ({ name, value }))
  const PAYMENT_COLORS = ['#4CAF50', '#5C6BC0', '#C9A227', '#E64E12', '#7C1D1B', '#9CA3AF']

  // ── Meal time breakdown (3 slots only) ────────────────────────────────────
  const MEAL_SLOTS = [
    { label: 'Breakfast', time: '5 AM – 12 PM', hours: [5,6,7,8,9,10,11],                      color: '#F59E0B', bg: '#FFFBEB', emoji: '🌅' },
    { label: 'Lunch',     time: '12 PM – 4 PM', hours: [12,13,14,15],                           color: '#EF4444', bg: '#FFF5F5', emoji: '☀️' },
    { label: 'Dinner',    time: '4 PM onwards', hours: [16,17,18,19,20,21,22,23,0,1,2,3,4],    color: '#7C1D1B', bg: '#FDF8F6', emoji: '🌙' },
  ]
  const mealCounts = { Breakfast: 0, Lunch: 0, Dinner: 0 }
  rangeOrders.forEach(o => {
    const t = readCreatedAt(o)
    if (!t) return
    const h = t.getHours()
    const slot = MEAL_SLOTS.find(s => s.hours.includes(h))
    if (slot) mealCounts[slot.label]++
  })
  const mealData = MEAL_SLOTS.map(s => ({ ...s, count: mealCounts[s.label] }))
  const mealTotal = mealData.reduce((s, m) => s + m.count, 0)
  const peakMeal = mealData.reduce((best, m) => m.count > best.count ? m : best, mealData[0])

  function exportCSV() {
    const rows = [
      ['Order ID', 'Date', 'Status', 'Items', 'Amount', 'Payment', 'Address'],
      ...rangeOrders.map(o => [
        o.id,
        readCreatedAt(o) ? format(readCreatedAt(o), 'yyyy-MM-dd HH:mm') : '',
        o.status || '',
        Array.isArray(o.items) ? o.items.map(i => `${i.name}×${i.qty || 1}`).join('; ') : '',
        readTotal(o),
        o.payment_mode || '',
        o.deliveryAddress || o.address || '',
      ])
    ]
    const csv = rows.map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `orders-${range}days-${format(now, 'yyyy-MM-dd')}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Reports</h1>
          <p className="page-subtitle">Analytics and business insights</p>
        </div>
        <div className="flex gap-3">
          <select
            className="input max-w-[160px]"
            value={range}
            onChange={e => setRange(e.target.value)}
          >
            <option value="7">Last 7 days</option>
            <option value="14">Last 14 days</option>
            <option value="30">Last 30 days</option>
            <option value="90">Last 90 days</option>
          </select>
          <button onClick={exportCSV} className="btn-primary whitespace-nowrap">
            ↓ Export CSV
          </button>
        </div>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: 'Total Revenue', value: fmtInr(totalRevenue), icon: '💰', color: 'bg-green-50' },
          { label: 'Total Orders', value: rangeOrders.length, icon: '🧾', color: 'bg-blue-50' },
          { label: 'Avg Order Value', value: fmtInr(avgOrderValue), icon: '📊', color: 'bg-purple-50' },
          { label: 'Delivered', value: deliveredCount, icon: '✅', color: 'bg-emerald-50' },
        ].map(c => (
          <div key={c.label} className="stat-card flex items-start gap-4">
            <div className={`w-11 h-11 rounded-xl flex items-center justify-center text-lg shrink-0 ${c.color}`}>{c.icon}</div>
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{c.label}</p>
              <p className="text-2xl font-bold text-gray-900 mt-0.5">{c.value}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Revenue chart */}
      <div className="section-card p-6">
        <h2 className="font-display font-bold text-lg text-maroon-deep mb-1">Daily Revenue</h2>
        <p className="text-sm text-gray-500 mb-5">Last {range} days</p>
        <ResponsiveContainer width="100%" height={220}>
          <AreaChart data={dailyData}>
            <defs>
              <linearGradient id="revGrad2" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#7C1D1B" stopOpacity={0.25} />
                <stop offset="95%" stopColor="#7C1D1B" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#E4D7C7" />
            <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false}
              interval={days > 14 ? Math.floor(days / 10) : 0} />
            <YAxis tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false} tickFormatter={v => '₹' + v} width={60} />
            <Tooltip formatter={v => [fmtInr(v), 'Revenue']} contentStyle={{ borderRadius: 12, border: '1px solid #E4D7C7', fontSize: 13 }} />
            <Area type="monotone" dataKey="revenue" stroke="#7C1D1B" strokeWidth={2.5} fill="url(#revGrad2)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Order count + Peak dishes */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Order count bar chart */}
        <div className="section-card p-6">
          <h2 className="font-display font-bold text-lg text-maroon-deep mb-1">Daily Orders</h2>
          <p className="text-sm text-gray-500 mb-5">Number of orders per day</p>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={dailyData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E4D7C7" vertical={false} />
              <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false}
                interval={days > 14 ? Math.floor(days / 10) : 0} />
              <YAxis tick={{ fontSize: 11, fill: '#9CA3AF' }} axisLine={false} tickLine={false} allowDecimals={false} />
              <Tooltip contentStyle={{ borderRadius: 12, border: '1px solid #E4D7C7', fontSize: 13 }} />
              <Bar dataKey="count" name="Orders" radius={[4, 4, 0, 0]}>
                {dailyData.map((_, i) => (
                  <Cell key={i} fill={i === dailyData.length - 1 ? '#7C1D1B' : '#C9A227'} opacity={0.85} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Peak dishes */}
        <div className="section-card p-6">
          <div className="flex items-center gap-2 mb-4">
            <span className="text-lg">🔥</span>
            <h2 className="font-display font-bold text-lg text-maroon-deep">Peak Dishes</h2>
          </div>
          {topDishes.length === 0 ? (
            <p className="text-sm text-gray-400 py-8 text-center">No data in this range</p>
          ) : (
            <div className="space-y-3">
              {topDishes.map(([name, qty], i) => {
                const maxQ = topDishes[0][1]
                const rankColors = ['text-amber-500', 'text-gray-400', 'text-amber-700']
                return (
                  <div key={name} className="flex items-center gap-3">
                    <span className={`text-xs font-bold w-5 shrink-0 ${rankColors[i] || 'text-maroon'}`}>#{i + 1}</span>
                    <div className="flex-1 min-w-0">
                      <div className="flex justify-between mb-1">
                        <span className="text-sm font-semibold text-gray-800 truncate">{name}</span>
                        <span className="text-xs font-bold text-gray-600 ml-2">{qty}</span>
                      </div>
                      <div className="h-2 bg-cream-border rounded-full overflow-hidden">
                        <div className="h-full rounded-full bg-maroon" style={{ width: `${(qty / maxQ) * 100}%`, opacity: 0.8 - i * 0.06 }} />
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>

      {/* Payment method donut + Meal time */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

        {/* Revenue by Payment Method — premium donut */}
        <div className="section-card p-6 flex flex-col">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-2xl bg-green-50 flex items-center justify-center text-xl shrink-0">💳</div>
            <div>
              <h2 className="font-display font-bold text-lg text-maroon-deep leading-tight">Revenue by Payment</h2>
              <p className="text-xs text-gray-400 mt-0.5">Last {range} days</p>
            </div>
          </div>

          {paymentData.length === 0 ? (
            <div className="flex-1 flex items-center justify-center py-10">
              <p className="text-sm text-gray-400">No payment data in this range</p>
            </div>
          ) : (
            <div className="flex flex-col items-center gap-5">
              {/* Donut with center total */}
              <div className="relative" style={{ width: 200, height: 200 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={paymentData}
                      dataKey="value"
                      innerRadius={62}
                      outerRadius={92}
                      paddingAngle={3}
                      startAngle={90}
                      endAngle={-270}
                      strokeWidth={0}
                    >
                      {paymentData.map((_, i) => (
                        <Cell key={i} fill={PAYMENT_COLORS[i % PAYMENT_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      formatter={v => [fmtInr(v), 'Revenue']}
                      contentStyle={{ borderRadius: 12, border: '1px solid #E4D7C7', fontSize: 12, boxShadow: '0 4px 16px rgba(0,0,0,0.08)' }}
                    />
                  </PieChart>
                </ResponsiveContainer>
                {/* Center label */}
                <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                  <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Total</p>
                  <p className="text-xl font-bold text-maroon-deep mt-0.5">{fmtInr(totalRevenue)}</p>
                </div>
              </div>

              {/* Legend rows */}
              <div className="w-full space-y-3">
                {paymentData.map((d, i) => {
                  const pct = totalRevenue > 0 ? Math.round((d.value / totalRevenue) * 100) : 0
                  const color = PAYMENT_COLORS[i % PAYMENT_COLORS.length]
                  return (
                    <div key={d.name} className="flex items-center gap-3">
                      <div className="w-3 h-3 rounded-full shrink-0" style={{ background: color }} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-baseline justify-between gap-2 mb-1.5">
                          <span className="text-sm font-semibold text-gray-700 truncate">{d.name}</span>
                          <div className="flex items-baseline gap-2 shrink-0">
                            <span className="text-xs text-gray-400">{fmtInr(d.value)}</span>
                            <span className="text-xs font-bold" style={{ color }}>{pct}%</span>
                          </div>
                        </div>
                        <div className="h-2 rounded-full overflow-hidden" style={{ background: color + '20' }}>
                          <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
                        </div>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          )}
        </div>

        {/* Meal Time — 3 big cards */}
        <div className="section-card p-6 flex flex-col">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-2xl bg-amber-50 flex items-center justify-center text-xl shrink-0">⏰</div>
            <div>
              <h2 className="font-display font-bold text-lg text-maroon-deep leading-tight">Orders by Meal Time</h2>
              <p className="text-xs text-gray-400 mt-0.5">Last {range} days &middot; when customers order most</p>
            </div>
          </div>

          {rangeOrders.length === 0 ? (
            <div className="flex-1 flex items-center justify-center py-10">
              <p className="text-sm text-gray-400">No data in this range</p>
            </div>
          ) : (
            <div className="flex flex-col gap-4 flex-1">
              {/* Three slot cards in a row */}
              <div className="grid grid-cols-3 gap-3">
                {mealData.map(slot => {
                  const pct = mealTotal > 0 ? Math.round((slot.count / mealTotal) * 100) : 0
                  const isPeak = slot.label === peakMeal.label && slot.count > 0
                  return (
                    <div key={slot.label}
                      className="rounded-2xl p-4 text-center relative overflow-hidden flex flex-col items-center"
                      style={{
                        background: isPeak ? slot.color + '12' : '#FAF6F0',
                        border: isPeak ? `2px solid ${slot.color}60` : '1.5px solid #EDE3D8',
                      }}>
                      {isPeak && (
                        <div className="absolute top-2 right-2">
                          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-md"
                            style={{ background: slot.color + '25', color: slot.color }}>Peak</span>
                        </div>
                      )}
                      <span className="text-2xl mb-2">{slot.emoji}</span>
                      <p className="text-xs font-bold text-gray-600 mb-1">{slot.label}</p>
                      <p className="text-3xl font-bold leading-none" style={{ color: isPeak ? slot.color : '#1F2937' }}>
                        {slot.count}
                      </p>
                      <p className="text-xs text-gray-400 mt-1 mb-3">orders</p>
                      <div className="w-full h-1.5 rounded-full overflow-hidden" style={{ background: slot.color + '20' }}>
                        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: slot.color }} />
                      </div>
                      <p className="text-xs font-bold mt-1.5" style={{ color: slot.color }}>{pct}%</p>
                    </div>
                  )
                })}
              </div>

              {/* Time labels below */}
              <div className="grid grid-cols-3 gap-3 text-center">
                {mealData.map(slot => (
                  <p key={slot.label} className="text-[11px] text-gray-400">{slot.time}</p>
                ))}
              </div>

              {/* Summary bar */}
              {mealTotal > 0 && (
                <div className="mt-2 rounded-xl overflow-hidden bg-cream-border flex" style={{ height: 8 }}>
                  {mealData.map(slot => {
                    const pct = mealTotal > 0 ? (slot.count / mealTotal) * 100 : 0
                    return <div key={slot.label} style={{ width: `${pct}%`, background: slot.color }} />
                  })}
                </div>
              )}
              {mealTotal > 0 && (
                <div className="flex justify-between text-xs text-gray-400 px-0.5">
                  {mealData.map(slot => (
                    <span key={slot.label} className="flex items-center gap-1">
                      <span className="w-2 h-2 rounded-full" style={{ background: slot.color }} />
                      {slot.label}
                    </span>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Status breakdown table */}
      <div className="section-card p-6">
        <h2 className="font-display font-bold text-lg text-maroon-deep mb-4">Order Status Breakdown</h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          {Object.entries(statusCounts).sort((a, b) => b[1] - a[1]).map(([status, count]) => (
            <div key={status} className="bg-cream rounded-xl p-4 text-center">
              <p className="text-2xl font-bold text-maroon-deep">{count}</p>
              <p className="text-xs text-gray-500 mt-1 capitalize">{status}</p>
              <p className="text-xs text-gray-400 mt-0.5">
                {rangeOrders.length > 0 ? Math.round((count / rangeOrders.length) * 100) : 0}%
              </p>
            </div>
          ))}
          {Object.keys(statusCounts).length === 0 && (
            <p className="col-span-6 text-sm text-gray-400 text-center py-4">No data in this range</p>
          )}
        </div>
      </div>
    </div>
  )
}
