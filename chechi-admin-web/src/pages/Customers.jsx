import { useEffect, useState } from 'react'
import { collection, query, limit, onSnapshot, orderBy, deleteDoc, doc } from 'firebase/firestore'
import { db } from '../firebase'
import { format } from 'date-fns'

function fmtInr(v) {
  const s = Math.round(v || 0).toString()
  if (s.length <= 3) return '₹' + s
  const last3 = s.slice(-3)
  const rest   = s.slice(0, -3)
  return '₹' + rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3
}

function readCreatedAt(m) {
  const t = m.created_at ?? m.createdAt ?? m.updatedAt
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

function readTotal(m) { return m.totalRupees ?? m.total ?? m.amount ?? 0 }

// Read location coords from Firestore user doc — mirrors Flutter's _coordsFromUserMap
function readCoords(u) {
  // location_geo is a Firestore GeoPoint — JS SDK gives it as { latitude, longitude }
  if (u.location_geo && typeof u.location_geo.latitude === 'number') {
    return { lat: u.location_geo.latitude, lng: u.location_geo.longitude }
  }
  const readNum = v => (typeof v === 'number' ? v : typeof v === 'string' ? parseFloat(v) || null : null)
  const lat = readNum(u.location_lat) ?? readNum(u.latitude) ?? readNum(u.lat)
  const lng = readNum(u.location_lng) ?? readNum(u.longitude) ?? readNum(u.lng)
  if (lat != null && lng != null) return { lat, lng }
  return null
}

// Read address string — mirrors Flutter's _locationFromUserMap
function readAddressLine(u) {
  if (u.location && u.location.trim()) return u.location.trim()
  if (u.addresses && typeof u.addresses === 'object') {
    for (const k of ['home', 'office', 'other']) {
      const s = u.addresses[k]
      if (s && s.trim()) return s.trim()
    }
  }
  return null
}

function MapEmbed({ lat, lng }) {
  const delta = 0.012
  const bbox  = `${lng - delta},${lat - delta},${lng + delta},${lat + delta}`
  const src   = `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat},${lng}`
  return (
    <div className="relative w-full rounded-xl overflow-hidden border border-cream-border" style={{ height: 240 }}>
      <iframe
        src={src}
        title="Customer location"
        className="w-full h-full border-0"
        loading="lazy"
        referrerPolicy="no-referrer"
      />
      {/* overlay prevents accidental scroll-hijack, opens map on click */}
      <a
        href={`https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=16/${lat}/${lng}`}
        target="_blank" rel="noopener noreferrer"
        className="absolute inset-0"
        style={{ opacity: 0 }}
        title="Open in OpenStreetMap"
      />
    </div>
  )
}

export default function Customers() {
  const [users, setUsers]     = useState([])
  const [orders, setOrders]   = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch]   = useState('')
  const [selected, setSelected] = useState(null)
  const [deleting, setDeleting] = useState(false)

  useEffect(() => {
    let usersLoaded = false, ordersLoaded = false
    const u1 = onSnapshot(query(collection(db, 'users'), limit(500)), snap => {
      setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      usersLoaded = true
      if (ordersLoaded) setLoading(false)
    })
    const u2 = onSnapshot(
      query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(500)),
      snap => {
        setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
        ordersLoaded = true
        if (usersLoaded) setLoading(false)
      }
    )
    return () => { u1(); u2() }
  }, [])

  // Enrich users with order stats + parsed location
  const enriched = users.map(u => {
    const userOrders = orders.filter(o => o.uid === u.id)
    const totalSpent = userOrders.reduce((s, o) => s + readTotal(o), 0)
    const lastOrderDoc = userOrders[0] || null
    const lastOrder    = lastOrderDoc ? readCreatedAt(lastOrderDoc) : null
    // Address: prefer last order's delivery_line, else user profile
    const deliveryLine = lastOrderDoc?.delivery_line?.trim() || null
    const profileAddr  = readAddressLine(u)
    const addressLine  = deliveryLine || profileAddr || null
    return {
      ...u,
      orderCount: userOrders.length,
      totalSpent,
      lastOrder,
      userOrders,
      coords:      readCoords(u),
      addressLine,
    }
  })

  const filtered = enriched.filter(u => {
    if (!search) return true
    const q = search.toLowerCase()
    return (u.displayName || '').toLowerCase().includes(q)
      || (u.mobile || '').includes(q)
      || (u.contactEmail || '').toLowerCase().includes(q)
      || (u.authPhone || '').includes(q)
      || (u.addressLine || '').toLowerCase().includes(q)
  })

  const selectedUser = selected ? enriched.find(u => u.id === selected) : null

  async function handleDelete(user) {
    if (!confirm(`Delete customer "${user.displayName || user.id}"?\n\nThis removes their profile from the database. Their past orders will remain.`)) return
    setDeleting(true)
    try {
      await deleteDoc(doc(db, 'users', user.id))
      setSelected(null)
    } catch (e) {
      alert(`Failed to delete: ${e.message}`)
    } finally {
      setDeleting(false)
    }
  }

  function googleMapsUrl(coords, address) {
    if (coords) return `https://www.google.com/maps/dir/?api=1&destination=${coords.lat},${coords.lng}&travelmode=driving`
    if (address) return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`
    return null
  }

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  return (
    <div className="space-y-5">
      <div className="flex flex-col sm:flex-row sm:items-center gap-4">
        <div className="flex-1">
          <h1 className="page-title">Customers</h1>
          <p className="page-subtitle">{users.length} registered customers</p>
        </div>
        <input className="input max-w-xs" placeholder="Search by name, mobile, address..." value={search} onChange={e => setSearch(e.target.value)} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Customer table */}
        <div className={`section-card ${selected ? 'lg:col-span-2' : 'lg:col-span-3'}`}>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-cream/60 border-b border-cream-border">
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer</th>
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Mobile</th>
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Orders</th>
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Total Spent</th>
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Last Order</th>
                  <th className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Location</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(u => (
                  <tr key={u.id}
                    className={`table-row cursor-pointer ${selected === u.id ? 'bg-cream' : ''}`}
                    onClick={() => setSelected(selected === u.id ? null : u.id)}>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-maroon/10 flex items-center justify-center text-maroon font-bold text-sm shrink-0">
                          {(u.displayName || '?').charAt(0).toUpperCase()}
                        </div>
                        <div>
                          <p className="font-semibold text-gray-900">{u.displayName || '—'}</p>
                          <p className="text-xs text-gray-400">{u.contactEmail || u.authEmail || ''}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-3.5 font-mono text-xs text-gray-700">{u.mobile || u.authPhone || '—'}</td>
                    <td className="px-5 py-3.5 text-gray-700 font-semibold">{u.orderCount}</td>
                    <td className="px-5 py-3.5 font-bold text-gray-900">{fmtInr(u.totalSpent)}</td>
                    <td className="px-5 py-3.5 text-gray-500 text-xs">{u.lastOrder ? format(u.lastOrder, 'd MMM yyyy') : '—'}</td>
                    <td className="px-5 py-3.5">
                      {u.coords
                        ? <span className="inline-flex items-center gap-1 text-xs font-semibold text-green-700 bg-green-50 px-2 py-1 rounded-lg">
                            <span className="w-1.5 h-1.5 rounded-full bg-green-500" />
                            GPS
                          </span>
                        : u.addressLine
                          ? <span className="text-xs text-gray-500 truncate max-w-[120px] block">{u.addressLine}</span>
                          : <span className="text-xs text-gray-300">—</span>}
                    </td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={6} className="px-6 py-12 text-center text-gray-400 text-sm">No customers found</td></tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
            Showing {filtered.length} of {users.length} customers
          </div>
        </div>

        {/* Customer detail panel */}
        {selectedUser && (
          <div className="section-card p-6 space-y-5 lg:col-span-1">
            {/* Header */}
            <div className="flex items-center justify-between">
              <h3 className="font-display font-bold text-lg text-maroon-deep">Customer Details</h3>
              <button onClick={() => setSelected(null)} className="text-gray-400 hover:text-gray-600 text-lg">&times;</button>
            </div>

            {/* Avatar + name */}
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-maroon/10 flex items-center justify-center text-maroon font-bold text-xl shrink-0">
                {(selectedUser.displayName || '?').charAt(0).toUpperCase()}
              </div>
              <div>
                <p className="font-bold text-gray-900">{selectedUser.displayName || '—'}</p>
                <p className="text-xs text-gray-500">{selectedUser.mobile || selectedUser.authPhone || '—'}</p>
                {selectedUser.contactEmail && <p className="text-xs text-gray-400">{selectedUser.contactEmail}</p>}
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-cream rounded-xl p-3 text-center">
                <p className="text-xl font-bold text-maroon-deep">{selectedUser.orderCount}</p>
                <p className="text-xs text-gray-500 mt-0.5">Orders</p>
              </div>
              <div className="bg-cream rounded-xl p-3 text-center">
                <p className="text-lg font-bold text-maroon-deep">{fmtInr(selectedUser.totalSpent)}</p>
                <p className="text-xs text-gray-500 mt-0.5">Total Spent</p>
              </div>
            </div>

            {/* Location / Map */}
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Location</p>

              {selectedUser.coords ? (
                <div className="space-y-2">
                  <MapEmbed lat={selectedUser.coords.lat} lng={selectedUser.coords.lng} />
                  <p className="text-xs text-gray-500 font-mono">
                    {selectedUser.coords.lat.toFixed(6)}, {selectedUser.coords.lng.toFixed(6)}
                  </p>
                  {selectedUser.addressLine && (
                    <p className="text-xs text-gray-600">{selectedUser.addressLine}</p>
                  )}
                  <a
                    href={googleMapsUrl(selectedUser.coords, selectedUser.addressLine)}
                    target="_blank" rel="noopener noreferrer"
                    className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl bg-maroon text-white text-xs font-bold hover:bg-maroon-deep transition-colors"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                    Get Directions in Google Maps
                  </a>
                </div>
              ) : selectedUser.addressLine ? (
                <div className="space-y-2">
                  <div className="bg-cream rounded-xl p-3">
                    <p className="text-sm text-gray-700">{selectedUser.addressLine}</p>
                  </div>
                  <a
                    href={googleMapsUrl(null, selectedUser.addressLine)}
                    target="_blank" rel="noopener noreferrer"
                    className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl bg-maroon text-white text-xs font-bold hover:bg-maroon-deep transition-colors"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                    Search in Google Maps
                  </a>
                </div>
              ) : (
                <p className="text-xs text-gray-400 py-2">No location data for this customer</p>
              )}
            </div>

            {/* Recent orders */}
            <div>
              <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Recent Orders</p>
              <div className="space-y-2 max-h-40 overflow-y-auto">
                {selectedUser.userOrders.slice(0, 10).map(o => {
                  const t = readCreatedAt(o)
                  return (
                    <div key={o.id} className="flex justify-between items-center text-xs py-1.5 border-b border-cream-border">
                      <span className="font-mono text-gray-600">#{o.id.slice(0, 8)}</span>
                      <span className="text-gray-500">{t ? format(t, 'd MMM') : '—'}</span>
                      <span className="font-bold text-gray-900">{fmtInr(readTotal(o))}</span>
                    </div>
                  )
                })}
                {selectedUser.userOrders.length === 0 && (
                  <p className="text-xs text-gray-400">No orders yet</p>
                )}
              </div>
            </div>

            {/* Delete */}
            <div className="pt-2 border-t border-cream-border">
              <button
                onClick={() => handleDelete(selectedUser)}
                disabled={deleting}
                className="w-full py-2.5 rounded-xl bg-red-50 border border-red-100 text-red-700 text-xs font-bold hover:bg-red-100 transition-colors disabled:opacity-50"
              >
                {deleting ? 'Deleting...' : 'Delete Customer Profile'}
              </button>
              <p className="text-xs text-gray-400 mt-1.5 text-center">Orders are kept. Only the profile is removed.</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
