import { useEffect, useState } from 'react'
import { doc, onSnapshot } from 'firebase/firestore'
import { signOut } from 'firebase/auth'
import { db, auth } from '../firebase'
import { Outlet, useLocation } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import Sidebar from './Sidebar'
import { format } from 'date-fns'
import { pageTransition } from '../motion'
import { useRole } from '../role'

const titles = {
  '/': 'Dashboard',
  '/orders': 'Orders',
  '/customers': 'Customers',
  '/menu': 'Menu',
  '/reports': 'Reports',
  '/chats': 'Support Chats',
  '/settings': 'Settings',
}

/**
 * The light the glass sits in. Three tinted blobs drifting slowly behind
 * everything — without this the translucent panels have nothing to refract
 * and read as flat grey.
 */
function Aurora() {
  return (
    <div className="fixed inset-0 overflow-hidden pointer-events-none" aria-hidden="true">
      <div
        className="aurora-blob"
        style={{
          width: 620, height: 620, top: '-14%', left: '-8%',
          background: 'radial-gradient(circle, rgba(234,122,44,0.5) 0%, transparent 68%)',
          animationDelay: '0s',
        }}
      />
      <div
        className="aurora-blob"
        style={{
          width: 540, height: 540, top: '38%', right: '-10%',
          background: 'radial-gradient(circle, rgba(201,162,39,0.42) 0%, transparent 68%)',
          animationDelay: '-9s',
        }}
      />
      <div
        className="aurora-blob"
        style={{
          width: 500, height: 500, bottom: '-16%', left: '32%',
          background: 'radial-gradient(circle, rgba(232,93,63,0.34) 0%, transparent 68%)',
          animationDelay: '-17s',
        }}
      />
    </div>
  )
}

/** Remote payment gate: app_access/status, written only by the developer. */
function useAppAccess() {
  const [access, setAccess] = useState({ state: 'ok' })
  useEffect(() => onSnapshot(
    doc(db, 'app_access', 'status'),
    (snap) => setAccess(snap.exists() ? snap.data() : { state: 'ok' }),
    () => setAccess({ state: 'ok' }), // never lock a shop over a flaky connection
  ), [])
  return access
}

const DEFAULT_ACCESS_MESSAGE =
  'The final payment for this app is still pending. Please clear the balance with Hephora Tech to continue using the admin panel.'

function AccessLocked({ access }) {
  return (
    <div className="min-h-screen bg-cream flex items-center justify-center p-6">
      <div className="max-w-md text-center space-y-4">
        <h1 className="font-display font-bold text-2xl text-maroon-deep">Payment pending</h1>
        <p className="text-gray-700">{access.message?.trim() || DEFAULT_ACCESS_MESSAGE}</p>
        {typeof access.amountDue === 'number' && (
          <p className="font-semibold text-maroon">Balance due: ₹{access.amountDue.toLocaleString('en-IN')}</p>
        )}
        {access.contact?.trim() && <p className="font-semibold">Contact: {access.contact.trim()}</p>}
        <button onClick={() => signOut(auth)} className="px-4 py-2 rounded-xl border border-gray-300 text-sm">
          Sign out
        </button>
      </div>
    </div>
  )
}

function AccessReminderModal({ access, onClose }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl text-center space-y-4">
        <div className="mx-auto w-12 h-12 rounded-full bg-amber-100 text-amber-700 flex items-center justify-center text-2xl font-bold">!</div>
        <h2 className="font-display font-bold text-xl text-maroon-deep">Payment reminder</h2>
        <p className="text-gray-700">{access.message?.trim() || DEFAULT_ACCESS_MESSAGE}</p>
        {typeof access.amountDue === 'number' && (
          <p className="font-semibold text-maroon">Balance due: ₹{access.amountDue.toLocaleString('en-IN')}</p>
        )}
        {access.contact?.trim() && <p className="font-semibold">Contact: {access.contact.trim()}</p>}
        <button onClick={onClose}
          className="w-full px-4 py-2.5 rounded-xl bg-maroon text-white font-semibold">
          OK, understood
        </button>
      </div>
    </div>
  )
}

export default function Layout({ user }) {
  const { isAdmin, staff } = useRole()
  const access = useAppAccess()
  const [reminderClosed, setReminderClosed] = useState(false)

  // Once dismissed, the reminder comes back every 15 minutes.
  useEffect(() => {
    if (!reminderClosed) return undefined
    const t = setTimeout(() => setReminderClosed(false), 15 * 60 * 1000)
    return () => clearTimeout(t)
  }, [reminderClosed])
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()
  const title = titles[location.pathname] ?? 'Admin'
  const initial = (staff?.name || user?.email || 'A').charAt(0).toUpperCase()

  if (access.state === 'locked') return <AccessLocked access={access} />

  return (
    <div className="relative flex h-screen overflow-hidden">
      {access.state === 'reminder' && !reminderClosed && (
        <AccessReminderModal access={access} onClose={() => setReminderClosed(true)} />
      )}
      <Aurora />

      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <div className="relative flex-1 flex flex-col min-w-0 overflow-hidden">
        {access.state === 'reminder' && (
          <div className="bg-amber-700 text-white text-sm px-4 py-2 shrink-0">
            {access.message?.trim() || DEFAULT_ACCESS_MESSAGE}
          </div>
        )}
        {/* Top bar */}
        <header className="glass-white px-6 py-3 flex items-center gap-4 shrink-0 sticky top-0 z-20
                           border-b border-white/60">
          <div className="flex items-center gap-3 min-w-0 shrink-0">
            <button
              onClick={() => setSidebarOpen(true)}
              className="lg:hidden p-2 rounded-xl hover:bg-white/60 transition-colors"
              aria-label="Open menu"
            >
              <div className="w-5 space-y-1.5">
                <span className="block h-0.5 bg-gray-500 rounded-full" />
                <span className="block h-0.5 bg-gray-500 rounded-full w-3.5" />
                <span className="block h-0.5 bg-gray-500 rounded-full" />
              </div>
            </button>
            <div className="min-w-0">
              <motion.h1
                key={title}
                initial={{ opacity: 0, y: -6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
                className="font-display font-bold text-xl text-maroon-deep leading-tight"
              >
                {title}
              </motion.h1>
              <p className="text-xs text-gray-400 hidden sm:block">
                {format(new Date(), 'EEEE, d MMM yyyy')}
              </p>
            </div>
          </div>

          {/* Search */}
          <div className="flex-1 max-w-sm mx-2 hidden md:flex items-center gap-2 rounded-xl px-3.5 py-2
                          bg-white/55 border border-white/80 backdrop-blur-md
                          focus-within:bg-white/90 focus-within:border-maroon/40 transition-all">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0"
              fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <input
              type="text"
              placeholder="Search orders, customers, items..."
              className="bg-transparent text-sm flex-1 outline-none text-gray-600 placeholder-gray-400 min-w-0"
            />
          </div>

          {/* Account */}
          <div className="flex items-center gap-2.5 shrink-0 ml-auto">
            <div className="text-right hidden sm:block">
              <p className="text-xs font-semibold text-gray-700 truncate max-w-[160px]">
                {staff?.name || user?.email || user?.phoneNumber || 'Admin'}
              </p>
              <p className="text-[10px] text-gray-400 uppercase tracking-wide font-semibold">
                {isAdmin ? 'Administrator' : 'Staff'}
              </p>
            </div>
            <motion.div
              whileHover={{ scale: 1.06 }}
              whileTap={{ scale: 0.95 }}
              className="w-9 h-9 rounded-full flex items-center justify-center text-white font-bold text-sm shrink-0 cursor-pointer"
              style={{
                background: 'linear-gradient(135deg, #9E2E2B 0%, #5D1F1A 100%)',
                boxShadow: '0 4px 14px rgba(124,29,27,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
              }}
            >
              {initial}
            </motion.div>
          </div>
        </header>

        {/* Page content — each route fades through rather than snapping. */}
        <main className="flex-1 overflow-y-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={pageTransition.initial}
              animate={pageTransition.animate}
              exit={pageTransition.exit}
              className="p-6"
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  )
}
