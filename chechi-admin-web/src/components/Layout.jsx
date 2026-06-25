import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar'
import { format } from 'date-fns'

const titles = {
  '/': 'Dashboard',
  '/orders': 'Orders',
  '/customers': 'Customers',
  '/menu': 'Menu',
  '/reports': 'Reports',
  '/chats': 'Support Chats',
  '/settings': 'Settings',
}

export default function Layout({ user }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()
  const title = titles[location.pathname] ?? 'Admin'

  return (
    <div className="flex h-screen overflow-hidden bg-cream">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top bar — sticky glass */}
        <header className="glass-white border-b border-cream-border px-6 py-3 flex items-center gap-4 shrink-0 sticky top-0 z-10">
          {/* Mobile hamburger + Title */}
          <div className="flex items-center gap-3 min-w-0 shrink-0">
            <button onClick={() => setSidebarOpen(true)} className="lg:hidden p-2 rounded-xl hover:bg-cream transition-colors">
              <div className="w-5 space-y-1.5">
                <span className="block h-0.5 bg-gray-500 rounded-full" />
                <span className="block h-0.5 bg-gray-500 rounded-full w-3.5" />
                <span className="block h-0.5 bg-gray-500 rounded-full" />
              </div>
            </button>
            <div className="min-w-0">
              <h1 className="font-display font-bold text-xl text-maroon-deep leading-tight">{title}</h1>
              <p className="text-xs text-gray-400 hidden sm:block">{format(new Date(), 'EEEE, d MMM yyyy')}</p>
            </div>
          </div>

          {/* Search bar */}
          <div className="flex-1 max-w-sm mx-2 hidden md:flex items-center gap-2 bg-cream border border-cream-border rounded-xl px-3.5 py-2">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-gray-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <input
              type="text"
              placeholder="Search orders, customers, items..."
              className="bg-transparent text-sm flex-1 outline-none text-gray-600 placeholder-gray-400 min-w-0"
            />
          </div>

          {/* Right icons */}
          <div className="flex items-center gap-2 shrink-0 ml-auto">
            <div className="text-right hidden sm:block">
              <p className="text-xs font-semibold text-gray-700 truncate max-w-[160px]">{user?.email || user?.phoneNumber || 'Admin'}</p>
              <p className="text-[10px] text-gray-400 uppercase tracking-wide font-semibold">Administrator</p>
            </div>
            <div className="w-9 h-9 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-sm shrink-0 cursor-pointer"
              style={{ background: 'linear-gradient(135deg, #7C1D1B 0%, #5D1F1A 100%)' }}>
              A
            </div>
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto">
          <div className="p-6">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  )
}
