import { useEffect, useState, useRef } from 'react'
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

// Mirrors Flutter's _coordsFromUserMap
function readCoords(u) {
  if (u.location_geo && typeof u.location_geo.latitude === 'number') {
    return { lat: u.location_geo.latitude, lng: u.location_geo.longitude }
  }
  const n = v => (typeof v === 'number' ? v : typeof v === 'string' ? parseFloat(v) || null : null)
  const lat = n(u.location_lat) ?? n(u.latitude) ?? n(u.lat)
  const lng = n(u.location_lng) ?? n(u.longitude) ?? n(u.lng)
  if (lat != null && lng != null) return { lat, lng }
  return null
}

// Mirrors Flutter's _locationFromUserMap
function readAddressLine(u) {
  const loc = (u.location || '').trim()
  if (loc) return loc
  if (u.addresses && typeof u.addresses === 'object') {
    for (const k of ['home', 'office', 'other']) {
      const s = (u.addresses[k] || '').trim()
      if (s) return s
    }
  }
  return null
}

// Free Nominatim geocoding (OpenStreetMap)
async function geocode(address) {
  try {
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(address)}&format=json&limit=1&countrycodes=in`
    const res  = await fetch(url, { headers: { 'Accept-Language': 'en', 'User-Agent': 'ChechiPuttuAdmin/1.0' } })
    const data = await res.json()
    if (data?.[0]) return { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) }
  } catch (_) {}
  return null
}

function MapEmbed({ lat, lng }) {
  const d   = 0.012
  const bbox = `${lng - d},${lat - d},${lng + d},${lat + d}`
  return (
    <div className="w-full rounded-xl overflow-hidden border border-cream-border" style={{ height: 220 }}>
      <iframe
        title="map"
        src={`https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat},${lng}`}
        className="w-full h-full border-0"
        loading="lazy"
      />
    </div>
  )
}

export default function Customers() {
  const [users, setUsers]       = useState([])
  const [orders, setOrders]     = useState([])
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [selected, setSelected] = useState(null)
  const [deleting, setDeleting] = useState(false)
  // geocoded coords cache: uid → {lat,lng} | null
  const [geocoded, setGeocoded] = useState({})
  const geocodingRef = useRef(new Set())

  useEffect(() => {
    let ul = false, ol = false
    const u1 = onSnapshot(query(collection(db, 'users'), limit(500)), snap => {
      setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      ul = true; if (ol) setLoading(false)
    })
    const u2 = onSnapshot(
      query(collection(db, 'orders'), orderBy('created_at', 'desc'), limit(500)),
      snap => {
        setOrders(snap.docs.map(d => ({ id: d.id, ...d.data() })))
        ol = true; if (ul) setLoading(false)
      }
    )
    return () => { u1(); u2() }
  }, [])

  const enriched = users.map(u => {
    const userOrders  = orders.filter(o => o.uid === u.id)
    const totalSpent  = userOrders.reduce((s, o) => s + readTotal(o), 0)
    const lastOrderDoc = userOrders[0] || null
    const lastOrder    = lastOrderDoc ? readCreatedAt(lastOrderDoc) : null
    const deliveryLine = (lastOrderDoc?.delivery_line || '').trim() || null
    const profileAddr  = readAddressLine(u)
    const addressLine  = deliveryLine || profileAddr || null
    return { ...u, orderCount: userOrders.length, totalSpent, lastOrder, userOrders,
      coords: readCoords(u), addressLine }
  })
  // Only accounts that finished sign-up, matching the Flutter admin app.
  // Sign-up asks for a name and a mobile number together, so an account
  // missing either never completed it and can only render as a nameless
  // "Customer" row. Anyone who has ordered is kept regardless — the kitchen
  // has to be able to find whoever placed that order.
  .filter(u => {
    if (u.orderCount > 0) return true
    const name = (u.displayName || '').trim()
    const mobile = (u.mobile || u.authPhone || '').trim()
    return name.length > 0 && mobile.length > 0
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

  // Geocode text address when detail panel opens and user has no GPS
  useEffect(() => {
    if (!selectedUser) return
    if (selectedUser.coords) return          // already has GPS
    const addr = selectedUser.addressLine
    if (!addr) return
    const uid = selectedUser.id
    if (geocoded[uid] !== undefined) return  // already cached
    if (geocodingRef.current.has(uid)) return
    geocodingRef.current.add(uid)
    geocode(addr).then(coords => {
      setGeocoded(prev => ({ ...prev, [uid]: coords }))
      geocodingRef.current.delete(uid)
    })
  }, [selectedUser?.id])

  // Resolved coords: GPS first, geocoded fallback
  const resolvedCoords = selectedUser
    ? selectedUser.coords ?? geocoded[selectedUser.id] ?? null
    : null
  const geocoding = selectedUser && !selectedUser.coords && selectedUser.addressLine && geocoded[selectedUser.id] === undefined

  async function handleDelete(user) {
    if (!confirm(`Delete "${user.displayName || user.id}"?\n\nRemoves their profile from the database. Past orders are kept.`)) return
    setDeleting(true)
    try {
      await deleteDoc(doc(db, 'users', user.id))
      setSelected(null)
    } catch (e) { alert(`Failed: ${e.message}`) }
    finally { setDeleting(false) }
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
        {/* Table */}
        <div className={`section-card ${selected ? 'lg:col-span-2' : 'lg:col-span-3'}`}>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-cream/60 border-b border-cream-border">
                  {['Customer', 'Mobile', 'Orders', 'Total Spent', 'Last Order'].map(h => (
                    <th key={h} className="text-left px-5 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
                  ))}
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
                          {u.addressLine && (
                            <p className="text-xs text-gray-400 truncate max-w-[180px]">{u.addressLine}</p>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-3.5 font-mono text-xs text-gray-700">{u.mobile || u.authPhone || '—'}</td>
                    <td className="px-5 py-3.5 font-semibold text-gray-700">{u.orderCount}</td>
                    <td className="px-5 py-3.5 font-bold text-gray-900">{fmtInr(u.totalSpent)}</td>
                    <td className="px-5 py-3.5 text-gray-500 text-xs">{u.lastOrder ? format(u.lastOrder, 'd MMM yyyy') : '—'}</td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={5} className="px-6 py-12 text-center text-gray-400 text-sm">No customers found</td></tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="px-5 py-3 border-t border-cream-border bg-cream/40 text-xs text-gray-400">
            Showing {filtered.length} of {enriched.length} customers &nbsp;·&nbsp; Click a row to view details
          </div>
        </div>

        {/* Detail panel */}
        {selectedUser && (
          <div className="section-card lg:col-span-1 flex flex-col max-h-screen overflow-y-auto">
            <div className="px-6 py-5 border-b border-cream-border flex items-center justify-between sticky top-0 bg-white z-10">
              <h3 className="font-display font-bold text-lg text-maroon-deep">Customer Details</h3>
              <button onClick={() => setSelected(null)} className="text-gray-400 hover:text-gray-600 text-xl">&times;</button>
            </div>

            <div className="p-6 space-y-5 flex-1">
              {/* Avatar + name */}
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-full bg-maroon/10 flex items-center justify-center text-maroon font-bold text-xl shrink-0">
                  {(selectedUser.displayName || '?').charAt(0).toUpperCase()}
                </div>
                <div>
                  <p className="font-bold text-gray-900 text-base">{selectedUser.displayName || '—'}</p>
                  <p className="text-sm text-gray-500">{selectedUser.mobile || selectedUser.authPhone || '—'}</p>
                  {selectedUser.contactEmail && <p className="text-xs text-gray-400">{selectedUser.contactEmail}</p>}
                </div>
              </div>

              {/* Stats */}
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-cream rounded-xl p-3 text-center">
                  <p className="text-2xl font-bold text-maroon-deep">{selectedUser.orderCount}</p>
                  <p className="text-xs text-gray-500 mt-0.5">Orders</p>
                </div>
                <div className="bg-cream rounded-xl p-3 text-center">
                  <p className="text-xl font-bold text-maroon-deep">{fmtInr(selectedUser.totalSpent)}</p>
                  <p className="text-xs text-gray-500 mt-0.5">Total Spent</p>
                </div>
              </div>

              {/* Map section */}
              {(selectedUser.coords || selectedUser.addressLine) && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Location</p>

                  {/* Address text */}
                  {selectedUser.addressLine && (
                    <p className="text-sm text-gray-700 mb-2 leading-snug">{selectedUser.addressLine}</p>
                  )}

                  {/* Map */}
                  {geocoding ? (
                    <div className="w-full rounded-xl border border-cream-border bg-cream flex items-center justify-center gap-2 text-sm text-gray-400" style={{ height: 220 }}>
                      <div className="w-4 h-4 border-2 border-maroon border-t-transparent rounded-full animate-spin" />
                      Finding on map...
                    </div>
                  ) : resolvedCoords ? (
                    <MapEmbed lat={resolvedCoords.lat} lng={resolvedCoords.lng} />
                  ) : (
                    <div className="w-full rounded-xl border border-cream-border bg-cream flex items-center justify-center text-sm text-gray-400" style={{ height: 100 }}>
                      Could not locate on map
                    </div>
                  )}

                  {/* GPS badge or geocoded note */}
                  {selectedUser.coords ? (
                    <p className="text-xs text-green-600 font-semibold mt-1.5">GPS location (exact)</p>
                  ) : resolvedCoords ? (
                    <p className="text-xs text-gray-400 mt-1.5">Approximate location from address</p>
                  ) : null}

                  {/* Google Maps directions button */}
                  {(resolvedCoords || selectedUser.addressLine) && (
                    <a
                      href={
                        resolvedCoords
                          ? `https://www.google.com/maps/dir/?api=1&destination=${resolvedCoords.lat},${resolvedCoords.lng}&travelmode=driving`
                          : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(selectedUser.addressLine)}`
                      }
                      target="_blank" rel="noopener noreferrer"
                      className="mt-3 flex items-center justify-center gap-2 w-full py-3 rounded-xl bg-maroon text-white text-sm font-bold hover:bg-maroon-deep transition-colors"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                      </svg>
                      Get Directions in Google Maps
                    </a>
                  )}
                </div>
              )}

              {!selectedUser.coords && !selectedUser.addressLine && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Location</p>
                  <p className="text-sm text-gray-400">No location saved for this customer</p>
                </div>
              )}

              {/* Recent orders */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Recent Orders</p>
                <div className="space-y-1.5 max-h-44 overflow-y-auto">
                  {selectedUser.userOrders.slice(0, 10).map(o => {
                    const t = readCreatedAt(o)
                    return (
                      <div key={o.id} className="flex justify-between items-center text-xs py-1.5 border-b border-cream-border">
                        <span className="font-mono text-gray-600">#{o.id.slice(0, 8)}</span>
                        <span className="text-gray-500">{t ? format(t, 'd MMM') : '—'}</span>
                        <span className="font-bold text-gray-900">{fmtInr(readTotal(o))}</span>
                        <span className={`badge text-xs capitalize ${
                          (o.status || '') === 'delivered' ? 'bg-green-50 text-green-700' :
                          (o.status || '') === 'cancelled' ? 'bg-gray-100 text-gray-500' :
                          'bg-amber-50 text-amber-700'
                        }`}>{o.status || 'placed'}</span>
                      </div>
                    )
                  })}
                  {selectedUser.userOrders.length === 0 && <p className="text-xs text-gray-400">No orders yet</p>}
                </div>
              </div>

              {/* Delete */}
              <div className="pt-4 border-t border-cream-border">
                <button
                  onClick={() => handleDelete(selectedUser)}
                  disabled={deleting}
                  className="w-full py-3 rounded-xl bg-red-50 border border-red-200 text-red-700 text-sm font-bold hover:bg-red-100 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                  {deleting ? 'Deleting...' : 'Delete Customer Profile'}
                </button>
                <p className="text-xs text-gray-400 mt-1.5 text-center">Orders are kept. Only the profile is removed.</p>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
