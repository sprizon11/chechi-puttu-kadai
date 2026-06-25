import { NavLink, useNavigate } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../firebase'

const nav = [
  { to: '/',          icon: '⊞',  label: 'Dashboard',  end: true },
  { to: '/orders',    icon: '🧾', label: 'Orders' },
  { to: '/customers', icon: '👥', label: 'Customers' },
  { to: '/menu',      icon: '🍽️', label: 'Menu' },
  { to: '/reports',   icon: '📊', label: 'Reports' },
  { to: '/settings',  icon: '⚙️', label: 'Settings' },
]

export default function Sidebar({ open, onClose }) {
  const navigate = useNavigate()

  async function handleLogout() {
    await signOut(auth)
    navigate('/login')
  }

  return (
    <>
      {/* Mobile overlay */}
      {open && (
        <div
          className="fixed inset-0 bg-black/40 z-20 lg:hidden"
          onClick={onClose}
        />
      )}

      <aside className={`
        fixed top-0 left-0 h-full w-64 z-30 flex flex-col
        bg-maroon-deep text-white shadow-2xl
        transition-transform duration-300
        ${open ? 'translate-x-0' : '-translate-x-full'}
        lg:translate-x-0 lg:static lg:z-auto
      `}>
        {/* Logo */}
        <div className="px-6 pt-7 pb-6 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-white/15 flex items-center justify-center text-xl">
              🍽️
            </div>
            <div>
              <p className="font-display font-bold text-base leading-tight text-white">Chechi Puttu</p>
              <p className="text-xs text-white/50 font-medium">Admin Panel</p>
            </div>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 px-3 py-5 space-y-1 overflow-y-auto">
          {nav.map(({ to, icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              onClick={onClose}
              className={({ isActive }) =>
                `flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold transition-all ${
                  isActive
                    ? 'bg-white text-maroon-deep shadow-sm'
                    : 'text-white/70 hover:text-white hover:bg-white/10'
                }`
              }
            >
              <span className="text-lg w-6 text-center">{icon}</span>
              {label}
            </NavLink>
          ))}
        </nav>

        {/* Logout */}
        <div className="px-3 pb-6">
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold text-white/60 hover:text-white hover:bg-white/10 transition-all"
          >
            <span className="text-lg w-6 text-center">↩</span>
            Log out
          </button>
        </div>
      </aside>
    </>
  )
}
