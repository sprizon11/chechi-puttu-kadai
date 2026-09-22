import { useEffect, useState } from 'react'
import { collection, onSnapshot, orderBy, query } from 'firebase/firestore'
import { httpsCallable } from 'firebase/functions'
import { db, functions } from '../firebase'

// Admin-only screen for staff logins. Accounts are created, removed and
// re-passworded by Cloud Functions (adminCreateStaff / adminDeleteStaff /
// adminSetStaffPassword); this screen only lists staff/{uid} and calls them.

const createStaff   = httpsCallable(functions, 'adminCreateStaff')
const deleteStaff   = httpsCallable(functions, 'adminDeleteStaff')
const setStaffPass  = httpsCallable(functions, 'adminSetStaffPassword')

const emptyForm = { name: '', email: '', phone: '', password: '' }

function errText(e) {
  // Callable errors carry the message thrown by the function.
  return e?.message?.replace(/^FirebaseError:\s*/, '') || 'Something went wrong. Try again.'
}

function PasswordInput({ value, onChange, autoFocus }) {
  const [show, setShow] = useState(false)
  return (
    <div className="relative">
      <input
        className="input w-full pr-16"
        type={show ? 'text' : 'password'}
        value={value}
        onChange={onChange}
        minLength={6}
        required
        autoFocus={autoFocus}
        autoComplete="new-password"
        placeholder="At least 6 characters"
      />
      <button type="button" onClick={() => setShow(s => !s)}
        className="absolute inset-y-0 right-0 px-3 text-xs font-semibold text-gray-400 hover:text-maroon-deep">
        {show ? 'Hide' : 'Show'}
      </button>
    </div>
  )
}

function Label({ children }) {
  return <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1 block">{children}</label>
}

export default function StaffManager() {
  const [staff, setStaff]     = useState([])
  const [loading, setLoading] = useState(true)
  const [view, setView]       = useState('list')   // 'list' | 'add' | { password: staffDoc }
  const [form, setForm]       = useState(emptyForm)
  const [newPass, setNewPass] = useState('')
  const [busy, setBusy]       = useState(null)
  const [error, setError]     = useState('')
  const [notice, setNotice]   = useState('')

  useEffect(() => {
    const q = query(collection(db, 'staff'), orderBy('created_at', 'desc'))
    return onSnapshot(q,
      snap => { setStaff(snap.docs.map(d => ({ uid: d.id, ...d.data() }))); setLoading(false) },
      () => setLoading(false))
  }, [])

  function flash(msg) {
    setNotice(msg)
    setTimeout(() => setNotice(''), 4000)
  }

  function goList() {
    setView('list'); setError(''); setForm(emptyForm); setNewPass('')
  }

  async function handleCreate(e) {
    e.preventDefault()
    setError('')
    const digits = form.phone.replace(/\D/g, '')
    if (digits.length !== 10 && !(digits.length === 12 && digits.startsWith('91'))) {
      setError('Enter a 10-digit mobile number.'); return
    }
    setBusy('create')
    try {
      await createStaff({ ...form, name: form.name.trim(), email: form.email.trim() })
      const name = form.name.trim()
      goList()
      flash(`${name} can now sign in with their email and password.`)
    } catch (e) { setError(errText(e)) }
    finally { setBusy(null) }
  }

  async function handleRemove(s) {
    if (!confirm(`Remove ${s.name}?\n\nTheir login is deleted and they are signed out straight away.`)) return
    setBusy(s.uid)
    try {
      await deleteStaff({ uid: s.uid })
      flash(`${s.name} was removed.`)
    } catch (e) { alert(errText(e)) }
    finally { setBusy(null) }
  }

  async function handleSetPassword(e) {
    e.preventDefault()
    const s = view.password
    setError(''); setBusy('password')
    try {
      await setStaffPass({ uid: s.uid, password: newPass })
      goList()
      flash(`Password changed for ${s.name}. Share the new one with them.`)
    } catch (e) { setError(errText(e)) }
    finally { setBusy(null) }
  }

  // ── Add staff ──
  if (view === 'add') return (
    <form onSubmit={handleCreate} className="space-y-3">
      <div>
        <Label>Name</Label>
        <input className="input w-full" value={form.name} required autoFocus maxLength={80}
          onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Lakshmi" />
      </div>
      <div>
        <Label>Email (used to sign in)</Label>
        <input className="input w-full" type="email" value={form.email} required autoComplete="off"
          onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="staff@example.com" />
      </div>
      <div>
        <Label>Mobile number</Label>
        <input className="input w-full" type="tel" value={form.phone} required
          onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="98765 43210" />
      </div>
      <div>
        <Label>Password</Label>
        <PasswordInput value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} />
      </div>
      <p className="text-xs text-gray-400 leading-snug">
        Staff can see every page, take orders forward and add or edit dishes.
        They cannot delete anything, cancel orders, or change business settings.
      </p>
      {error && <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</p>}
      <div className="flex gap-2 pt-1">
        <button type="button" className="btn-ghost flex-1" onClick={goList}>Back</button>
        <button type="submit" className="btn-primary flex-1" disabled={busy === 'create'}>
          {busy === 'create' ? 'Creating…' : 'Create staff login'}
        </button>
      </div>
    </form>
  )

  // ── Change a staff member's password ──
  if (view?.password) return (
    <form onSubmit={handleSetPassword} className="space-y-3">
      <p className="text-sm text-gray-600">
        New password for <span className="font-bold text-gray-900">{view.password.name}</span> ({view.password.email}).
        They will be signed out and need the new password to sign in again.
      </p>
      <PasswordInput value={newPass} onChange={e => setNewPass(e.target.value)} autoFocus />
      {error && <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</p>}
      <div className="flex gap-2 pt-1">
        <button type="button" className="btn-ghost flex-1" onClick={goList}>Back</button>
        <button type="submit" className="btn-primary flex-1" disabled={busy === 'password'}>
          {busy === 'password' ? 'Saving…' : 'Change password'}
        </button>
      </div>
    </form>
  )

  // ── List ──
  return (
    <div className="space-y-3">
      {notice && <p className="text-sm text-green-700 bg-green-50 border border-green-200 rounded-xl px-3 py-2">{notice}</p>}

      {loading ? (
        <div className="flex justify-center py-8">
          <div className="w-6 h-6 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
        </div>
      ) : staff.length === 0 ? (
        <p className="text-sm text-gray-400 text-center py-6">No staff yet. Add someone to give them their own login.</p>
      ) : (
        <div className="divide-y divide-cream-border border border-cream-border rounded-xl max-h-[50vh] overflow-y-auto">
          {staff.map(s => (
            <div key={s.uid} className="flex items-center gap-3 px-3 py-3">
              <div className="w-9 h-9 rounded-full bg-maroon/10 text-maroon-deep font-bold flex items-center justify-center shrink-0">
                {(s.name || '?').charAt(0).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-gray-900 truncate">{s.name}</p>
                <p className="text-xs text-gray-400 truncate">{s.email} · {s.phone}</p>
              </div>
              <div className="flex gap-1.5 shrink-0">
                <button type="button" onClick={() => { setError(''); setNewPass(''); setView({ password: s }) }}
                  className="text-xs px-2.5 py-1.5 rounded-lg bg-cream border border-cream-border text-gray-700 hover:bg-cream-border font-semibold">
                  Password
                </button>
                <button type="button" onClick={() => handleRemove(s)} disabled={busy === s.uid}
                  className="text-xs px-2.5 py-1.5 rounded-lg bg-red-50 border border-red-100 text-red-600 hover:bg-red-100 font-semibold disabled:opacity-50">
                  {busy === s.uid ? 'Removing…' : 'Remove'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <button type="button" className="btn-primary w-full py-3" onClick={() => { setError(''); setView('add') }}>
        + Add staff
      </button>
    </div>
  )
}
