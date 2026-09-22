import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useState, useEffect } from 'react'
import { onAuthStateChanged, signOut } from 'firebase/auth'
import { auth } from './firebase'
import { resolveRole, RoleContext } from './role'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Orders from './pages/Orders'
import Customers from './pages/Customers'
import Menu from './pages/Menu'
import Reports from './pages/Reports'
import Settings from './pages/Settings'
import Chats from './pages/Chats'

function ProtectedRoute({ session, children }) {
  if (session === undefined) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }
  if (!session?.role) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  // undefined while loading; then { user, role, staff } — role is null when
  // nobody is signed in or the account has no access.
  const [session, setSession] = useState(undefined)
  const [noAccess, setNoAccess] = useState(false)

  useEffect(() => {
    return onAuthStateChanged(auth, async (u) => {
      if (!u) { setSession({ user: null, role: null, staff: null }); return }
      const { role, staff } = await resolveRole(u).catch(() => ({ role: null, staff: null }))
      if (!role) {
        // A customer or removed staff account: do not leave it signed in here.
        setNoAccess(true)
        await signOut(auth)
        return
      }
      setNoAccess(false)
      setSession({ user: u, role, staff })
    })
  }, [])

  const user = session?.user

  return (
    <RoleContext.Provider value={{ role: session?.role ?? null, staff: session?.staff ?? null }}>
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={
          session?.role ? <Navigate to="/" replace /> : <Login noAccess={noAccess} />
        } />
        <Route path="/" element={
          <ProtectedRoute session={session}>
            <Layout user={user} />
          </ProtectedRoute>
        }>
          <Route index element={<Dashboard />} />
          <Route path="orders" element={<Orders />} />
          <Route path="customers" element={<Customers />} />
          <Route path="menu" element={<Menu />} />
          <Route path="reports" element={<Reports />} />
          <Route path="settings" element={<Settings />} />
          <Route path="chats" element={<Chats />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
    </RoleContext.Provider>
  )
}
