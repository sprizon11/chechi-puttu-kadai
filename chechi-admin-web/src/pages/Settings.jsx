import { useEffect, useState } from 'react'
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore'
import { sendPasswordResetEmail } from 'firebase/auth'
import { db, auth } from '../firebase'
import { useNavigate } from 'react-router-dom'

// ── Tile component (matches Flutter's _SettingsTile) ─────────────────────────
function Tile({ icon, iconBg, title, sub, trailing, onClick, danger }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full flex items-center gap-4 px-4 py-3.5 hover:bg-cream/60 transition-colors text-left border-b border-cream-border last:border-0 ${danger ? 'group' : ''}`}
    >
      <div className="w-10 h-10 rounded-full flex items-center justify-center shrink-0 text-lg" style={{ background: iconBg }}>
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-sm font-bold ${danger ? 'text-red-700' : 'text-gray-900'}`}>{title}</p>
        {sub && <p className="text-xs text-gray-400 mt-0.5 leading-snug">{sub}</p>}
      </div>
      {trailing
        ? <span className="text-xs text-gray-400 font-semibold shrink-0">{trailing}</span>
        : <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-300 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
      }
    </button>
  )
}

function Section({ title, children }) {
  return (
    <div className="section-card overflow-hidden">
      <div className="px-4 pt-4 pb-1">
        <p className="font-display font-bold text-lg text-maroon-deep">{title}</p>
      </div>
      <div>{children}</div>
    </div>
  )
}

// ── Modal / sheet helper ──────────────────────────────────────────────────────
function Modal({ title, sub, onClose, children }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-lg p-6" onClick={e => e.stopPropagation()}>
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="font-display font-bold text-xl text-maroon-deep">{title}</h3>
            {sub && <p className="text-sm text-gray-400 mt-0.5">{sub}</p>}
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none ml-4">&times;</button>
        </div>
        {children}
      </div>
    </div>
  )
}

// ── Business profile form ─────────────────────────────────────────────────────
function BusinessModal({ form, setForm, onSave, onClose, saving, saved }) {
  return (
    <Modal title="Business Profile" sub="Shop details shown to customers" onClose={onClose}>
      <div className="space-y-3">
        {[
          { label: 'Shop Name', key: 'shopName', type: 'text' },
          { label: 'Phone', key: 'phone', type: 'tel', placeholder: '+91 XXXXX XXXXX' },
          { label: 'Email', key: 'email', type: 'email', placeholder: 'shop@example.com' },
        ].map(f => (
          <div key={f.key}>
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">{f.label}</label>
            <input className="input w-full" type={f.type} value={form[f.key] || ''} placeholder={f.placeholder}
              onChange={e => setForm(p => ({ ...p, [f.key]: e.target.value }))} />
          </div>
        ))}
        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">Address</label>
          <textarea className="input w-full resize-none" rows={2} value={form.address || ''}
            onChange={e => setForm(p => ({ ...p, address: e.target.value }))} placeholder="Full shop address" />
        </div>
        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">Announcement</label>
          <textarea className="input w-full resize-none" rows={2} value={form.announcement || ''}
            onChange={e => setForm(p => ({ ...p, announcement: e.target.value }))}
            placeholder="e.g. Closed on Sundays — shown to customers at top of app" />
        </div>
      </div>
      <div className="flex items-center gap-3 mt-5">
        <button onClick={onSave} disabled={saving} className="btn-primary flex-1 py-3">
          {saving ? 'Saving…' : 'Save'}
        </button>
        {saved && <span className="text-sm text-green-600 font-semibold">Saved!</span>}
      </div>
    </Modal>
  )
}

// ── Delivery settings form ────────────────────────────────────────────────────
function DeliveryModal({ form, setForm, onSave, onClose, saving, saved }) {
  function Toggle({ checked, onChange }) {
    return (
      <button type="button" onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${checked ? 'bg-maroon' : 'bg-gray-200'}`}>
        <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${checked ? 'translate-x-6' : 'translate-x-1'}`} />
      </button>
    )
  }
  function NumInput({ label, field, step, min }) {
    return (
      <div className="flex items-center justify-between py-2.5 border-b border-cream-border last:border-0">
        <p className="text-sm font-semibold text-gray-800">{label}</p>
        <input className="input max-w-[100px] text-right" type="number" min={min ?? 0} step={step ?? 1}
          value={form[field] || 0} onChange={e => setForm(p => ({ ...p, [field]: e.target.value }))} />
      </div>
    )
  }
  return (
    <Modal title="Delivery Settings" sub="Fees, radius and order toggles" onClose={onClose}>
      <div className="space-y-0">
        {[
          { label: 'Delivery Enabled', key: 'deliveryEnabled' },
          { label: 'Takeaway Enabled', key: 'takeawayEnabled' },
          { label: 'Scheduled Orders', key: 'scheduledOrdersEnabled' },
        ].map(f => (
          <div key={f.key} className="flex items-center justify-between py-3 border-b border-cream-border">
            <p className="text-sm font-semibold text-gray-800">{f.label}</p>
            <Toggle checked={!!form[f.key]} onChange={v => setForm(p => ({ ...p, [f.key]: v }))} />
          </div>
        ))}
        <NumInput label="Delivery Radius (km)" field="deliveryRadiusKm" step={0.5} min={1} />
        <NumInput label="Minimum Order (₹)" field="minOrderRupees" step={10} />
        <NumInput label="Delivery Charge (₹)" field="deliveryFeeRupees" step={5} />
        <NumInput label="Packing Charge (₹)" field="packagingFeeRupees" step={5} />
        <p className="text-xs text-gray-400 pt-2 leading-snug">
          Delivery + packing are added to every order and shown on the customer
          invoice. Total extra now: ₹
          {(parseFloat(form.deliveryFeeRupees) || 0) + (parseFloat(form.packagingFeeRupees) || 0)}
        </p>
      </div>
      <div className="flex items-center gap-3 mt-5">
        <button onClick={onSave} disabled={saving} className="btn-primary flex-1 py-3">
          {saving ? 'Saving…' : 'Save'}
        </button>
        {saved && <span className="text-sm text-green-600 font-semibold">Saved!</span>}
      </div>
    </Modal>
  )
}

// ── Operating hours ───────────────────────────────────────────────────────────
function HoursModal({ form, setForm, onSave, onClose, saving, saved }) {
  return (
    <Modal title="Operating Hours" sub="Daily open and close time" onClose={onClose}>
      <div className="space-y-4">
        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">Opening Time</label>
          <input className="input" type="time" value={form.openTime || '06:00'}
            onChange={e => setForm(p => ({ ...p, openTime: e.target.value }))} />
        </div>
        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">Closing Time</label>
          <input className="input" type="time" value={form.closeTime || '21:00'}
            onChange={e => setForm(p => ({ ...p, closeTime: e.target.value }))} />
        </div>
      </div>
      <div className="flex items-center gap-3 mt-5">
        <button onClick={onSave} disabled={saving} className="btn-primary flex-1 py-3">
          {saving ? 'Saving…' : 'Save'}
        </button>
        {saved && <span className="text-sm text-green-600 font-semibold">Saved!</span>}
      </div>
    </Modal>
  )
}

// ── Main Settings page ────────────────────────────────────────────────────────
export default function Settings() {
  const navigate = useNavigate()
  const [form, setForm] = useState({
    shopName: 'Chechi Puttu Kadai',
    phone: '', email: '', address: '', announcement: '',
    openTime: '06:00', closeTime: '21:00',
    deliveryRadiusKm: '10', minOrderRupees: '0',
    deliveryFeeRupees: '40', packagingFeeRupees: '20',
    deliveryEnabled: true, takeawayEnabled: true, scheduledOrdersEnabled: true,
  })
  const [loaded, setLoaded] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved,  setSaved]  = useState(false)
  const [modal,  setModal]  = useState(null)   // 'business' | 'delivery' | 'hours'
  const [pwMsg,  setPwMsg]  = useState('')

  useEffect(() => {
    Promise.all([
      getDoc(doc(db, 'admin_public', '__settings__')).catch(() => null),
      // Canonical charges doc — what the customer app and Cloud Functions read.
      getDoc(doc(db, 'admin_public', 'order_charges')).catch(() => null),
    ])
      .then(([settingsSnap, chargesSnap]) => {
        setForm(f => {
          const next = { ...f }
          if (settingsSnap?.exists()) Object.assign(next, settingsSnap.data())
          if (chargesSnap?.exists()) {
            const c = chargesSnap.data()
            if (c.delivery_rupees != null) next.deliveryFeeRupees = String(c.delivery_rupees)
            if (c.packing_rupees != null) next.packagingFeeRupees = String(c.packing_rupees)
          }
          return next
        })
      })
      .finally(() => setLoaded(true))
  }, [])

  async function saveForm() {
    setSaving(true); setSaved(false)
    const deliveryRupees = Math.max(0, Math.round(parseFloat(form.deliveryFeeRupees) || 0))
    const packingRupees = Math.max(0, Math.round(parseFloat(form.packagingFeeRupees) || 0))
    try {
      // Charges live in their own doc so the app and Cloud Functions read one
      // source of truth; __settings__ keeps a copy for the rest of this form.
      await setDoc(doc(db, 'admin_public', 'order_charges'), {
        delivery_rupees: deliveryRupees,
        packing_rupees: packingRupees,
        updatedAt: serverTimestamp(),
        updatedBy: auth.currentUser?.uid || null,
      }, { merge: true })
      await setDoc(doc(db, 'admin_public', '__settings__'), {
        ...form,
        deliveryRadiusKm:    parseFloat(form.deliveryRadiusKm) || 10,
        minOrderRupees:      parseFloat(form.minOrderRupees) || 0,
        deliveryFeeRupees:   deliveryRupees,
        packagingFeeRupees:  packingRupees,
        updatedAt: serverTimestamp(),
      }, { merge: true })
      setSaved(true)
      setTimeout(() => { setSaved(false); setModal(null) }, 2000)
    } finally { setSaving(false) }
  }

  async function sendPasswordReset() {
    const user = auth.currentUser
    const email = user?.email
    if (!email) { setPwMsg('No email linked to this account.'); return }
    try {
      await sendPasswordResetEmail(auth, email)
      setPwMsg(`Reset link sent to ${email}`)
    } catch (e) { setPwMsg(`Error: ${e.message}`) }
    setTimeout(() => setPwMsg(''), 5000)
  }

  function infoAlert(title, body) {
    alert(`${title}\n\n${body}`)
  }

  if (!loaded) return (
    <div className="flex items-center justify-center h-64">
      <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
    </div>
  )

  const hoursLabel = `${form.openTime || '06:00'} – ${form.closeTime || '21:00'}`
  const deliveryLabel = `Delivery ₹${form.deliveryFeeRupees || 0} + Packing ₹${form.packagingFeeRupees || 0} per order · Delivery ${form.deliveryEnabled ? 'on' : 'off'}`

  return (
    <div className="max-w-2xl space-y-4">
      <div>
        <h1 className="page-title">Settings</h1>
        <p className="page-subtitle">Manage your account, preferences and business settings</p>
      </div>

      {/* ── Account ──────────────────────────────────────── */}
      <Section title="Account">
        <Tile icon="👤" iconBg="#FFF0E6" title="Profile Information"
          sub={auth.currentUser?.email || auth.currentUser?.phoneNumber || 'Admin account'}
          onClick={() => infoAlert('Profile Information', `Signed in as: ${auth.currentUser?.email || auth.currentUser?.phoneNumber}\nUID: ${auth.currentUser?.uid}`)} />
        <Tile icon="🔒" iconBg="#E8F5E9" title="Change Password"
          sub={pwMsg || 'Send a password reset link to your email'}
          onClick={sendPasswordReset} />
        <Tile icon="👥" iconBg="#F3E5F5" title="Manage Staff"
          sub="Add or remove staff accounts"
          onClick={() => infoAlert('Manage Staff', 'Staff management is handled via Firebase Authentication.\nAdd staff emails in Firebase Console → Authentication.')} />
      </Section>

      {/* ── Business Settings ────────────────────────────── */}
      <Section title="Business Settings">
        <Tile icon="🏪" iconBg="#FFF0E6" title="Business Profile"
          sub={form.shopName || 'Chechi Puttu Kadai'}
          onClick={() => setModal('business')} />
        <Tile icon="⏰" iconBg="#FFF0E6" title="Operating Hours"
          sub={hoursLabel}
          onClick={() => setModal('hours')} />
        <Tile icon="🛵" iconBg="#E8F5E9" title="Delivery Settings"
          sub={deliveryLabel}
          onClick={() => setModal('delivery')} />
        <Tile icon="🍽️" iconBg="#E3F2FD" title="Menu Management"
          sub="Manage dishes, categories and pricing"
          onClick={() => navigate('/menu')} />
        <Tile icon="💬" iconBg="#F3E5F5" title="Customer Support Chats"
          sub="View and reply to customer messages"
          onClick={() => navigate('/chats')} />
      </Section>

      {/* ── Preferences ─────────────────────────────────── */}
      <Section title="Preferences">
        <Tile icon="🔔" iconBg="#E8F5E9" title="Notifications"
          sub="Order alerts, payout and status updates"
          onClick={() => infoAlert('Notifications', 'Push notification settings are managed in the Flutter admin app on your device.')} />
        <Tile icon="🌐" iconBg="#E3F2FD" title="Language"
          sub="English" trailing="English"
          onClick={() => infoAlert('Language', 'The web admin panel is in English.\nLanguage preference for the mobile app is set inside the Flutter admin app.')} />
      </Section>

      {/* ── Support & Others ─────────────────────────────── */}
      <Section title="Support & Others">
        <Tile icon="❓" iconBg="#E8F5E9" title="Help & Support"
          sub="Get help or contact us"
          onClick={() => window.open('mailto:support@chechiputtukadai.com?subject=Admin%20Support', '_blank')} />
        <Tile icon="🔏" iconBg="#E3F2FD" title="Privacy Policy"
          sub="Read our privacy policy"
          onClick={() => infoAlert('Privacy Policy', 'Your data is used only for order processing, account management and service improvement.')} />
        <Tile icon="📄" iconBg="#F3E5F5" title="Terms & Conditions"
          sub="Read our terms and conditions"
          onClick={() => infoAlert('Terms & Conditions', 'Use the app responsibly. Orders, pricing and availability are subject to operational updates.')} />
        <Tile icon="🚪" iconBg="#FFEBEE" title="Log Out" sub="Sign out from your account"
          danger onClick={async () => { const { signOut } = await import('firebase/auth'); await signOut(auth); navigate('/login') }} />
      </Section>

      <p className="text-center text-xs text-gray-400 pb-4">Chechi Puttu Kadai Admin · v1.2.3</p>

      {/* ── Modals ──────────────────────────────────────── */}
      {modal === 'business'  && <BusinessModal  form={form} setForm={setForm} onSave={saveForm} onClose={() => setModal(null)} saving={saving} saved={saved} />}
      {modal === 'delivery'  && <DeliveryModal  form={form} setForm={setForm} onSave={saveForm} onClose={() => setModal(null)} saving={saving} saved={saved} />}
      {modal === 'hours'     && <HoursModal     form={form} setForm={setForm} onSave={saveForm} onClose={() => setModal(null)} saving={saving} saved={saved} />}
    </div>
  )
}
