import { useEffect, useState } from 'react'
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../firebase'

export default function Settings() {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const [form, setForm] = useState({
    shopName: 'Chechi Puttu Kadai',
    phone: '',
    email: '',
    address: '',
    openTime: '06:00',
    closeTime: '21:00',
    deliveryRadiusKm: '10',
    minOrderRupees: '0',
    deliveryFeeRupees: '30',
    packagingFeeRupees: '10',
    deliveryEnabled: true,
    takeawayEnabled: true,
    scheduledOrdersEnabled: true,
    announcement: '',
  })

  useEffect(() => {
    getDoc(doc(db, 'admin_public', '__settings__'))
      .then(snap => {
        if (snap.exists()) setForm(f => ({ ...f, ...snap.data() }))
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  async function handleSave(e) {
    e.preventDefault()
    setSaving(true)
    setSaved(false)
    try {
      await setDoc(doc(db, 'admin_public', '__settings__'), {
        ...form,
        deliveryRadiusKm: parseFloat(form.deliveryRadiusKm) || 10,
        minOrderRupees: parseFloat(form.minOrderRupees) || 0,
        deliveryFeeRupees: parseFloat(form.deliveryFeeRupees) || 0,
        packagingFeeRupees: parseFloat(form.packagingFeeRupees) || 0,
        updatedAt: serverTimestamp(),
      }, { merge: true })
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    } finally {
      setSaving(false)
    }
  }

  function Field({ label, sub, children }) {
    return (
      <div className="flex flex-col sm:flex-row sm:items-start gap-4 py-5 border-b border-cream-border last:border-0">
        <div className="sm:w-56 shrink-0">
          <p className="text-sm font-semibold text-gray-800">{label}</p>
          {sub && <p className="text-xs text-gray-400 mt-0.5">{sub}</p>}
        </div>
        <div className="flex-1">{children}</div>
      </div>
    )
  }

  function Toggle({ checked, onChange }) {
    return (
      <button
        type="button"
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${checked ? 'bg-maroon' : 'bg-gray-200'}`}
      >
        <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${checked ? 'translate-x-6' : 'translate-x-1'}`} />
      </button>
    )
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h1 className="page-title">Settings</h1>
        <p className="page-subtitle">Manage shop configuration and delivery settings</p>
      </div>

      <form onSubmit={handleSave} className="space-y-6">
        {/* Shop Info */}
        <div className="section-card px-6">
          <h2 className="font-display font-bold text-lg text-maroon-deep pt-5 pb-1">Shop Information</h2>
          <p className="text-sm text-gray-400 pb-4">Basic details shown to customers</p>

          <Field label="Shop Name">
            <input className="input" value={form.shopName} onChange={e => setForm({ ...form, shopName: e.target.value })} />
          </Field>
          <Field label="Contact Phone">
            <input className="input" value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} placeholder="+91 XXXXX XXXXX" />
          </Field>
          <Field label="Contact Email">
            <input className="input" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} placeholder="shop@example.com" />
          </Field>
          <Field label="Address">
            <textarea className="input resize-none" rows={2} value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} placeholder="Full shop address" />
          </Field>
          <Field label="Announcement" sub="Shown at top of app for customers">
            <textarea className="input resize-none" rows={2} value={form.announcement} onChange={e => setForm({ ...form, announcement: e.target.value })} placeholder="e.g. Closed on Sundays" />
          </Field>
        </div>

        {/* Hours */}
        <div className="section-card px-6">
          <h2 className="font-display font-bold text-lg text-maroon-deep pt-5 pb-1">Operating Hours</h2>
          <p className="text-sm text-gray-400 pb-4">Set daily open and close time</p>

          <Field label="Opening Time">
            <input className="input max-w-[140px]" type="time" value={form.openTime} onChange={e => setForm({ ...form, openTime: e.target.value })} />
          </Field>
          <Field label="Closing Time">
            <input className="input max-w-[140px]" type="time" value={form.closeTime} onChange={e => setForm({ ...form, closeTime: e.target.value })} />
          </Field>
        </div>

        {/* Delivery */}
        <div className="section-card px-6">
          <h2 className="font-display font-bold text-lg text-maroon-deep pt-5 pb-1">Delivery Settings</h2>
          <p className="text-sm text-gray-400 pb-4">Fees, radius, and toggles</p>

          <Field label="Delivery Enabled" sub="Allow home delivery orders">
            <Toggle checked={form.deliveryEnabled} onChange={v => setForm({ ...form, deliveryEnabled: v })} />
          </Field>
          <Field label="Takeaway Enabled" sub="Allow in-store pickup orders">
            <Toggle checked={form.takeawayEnabled} onChange={v => setForm({ ...form, takeawayEnabled: v })} />
          </Field>
          <Field label="Scheduled Orders" sub="Allow customers to order for later">
            <Toggle checked={form.scheduledOrdersEnabled} onChange={v => setForm({ ...form, scheduledOrdersEnabled: v })} />
          </Field>
          <Field label="Delivery Radius" sub="Maximum distance from shop (km)">
            <input className="input max-w-[120px]" type="number" min="1" step="0.5" value={form.deliveryRadiusKm} onChange={e => setForm({ ...form, deliveryRadiusKm: e.target.value })} />
          </Field>
          <Field label="Minimum Order (₹)" sub="Minimum cart value for delivery">
            <input className="input max-w-[120px]" type="number" min="0" step="10" value={form.minOrderRupees} onChange={e => setForm({ ...form, minOrderRupees: e.target.value })} />
          </Field>
          <Field label="Delivery Fee (₹)">
            <input className="input max-w-[120px]" type="number" min="0" step="5" value={form.deliveryFeeRupees} onChange={e => setForm({ ...form, deliveryFeeRupees: e.target.value })} />
          </Field>
          <Field label="Packaging Fee (₹)">
            <input className="input max-w-[120px]" type="number" min="0" step="5" value={form.packagingFeeRupees} onChange={e => setForm({ ...form, packagingFeeRupees: e.target.value })} />
          </Field>
        </div>

        <div className="flex items-center gap-4">
          <button type="submit" disabled={saving} className="btn-primary px-8 py-3">
            {saving ? 'Saving…' : 'Save Settings'}
          </button>
          {saved && (
            <span className="text-sm font-semibold text-green-600 flex items-center gap-1.5">
              ✓ Settings saved
            </span>
          )}
        </div>
      </form>
    </div>
  )
}
