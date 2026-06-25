import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useState, useEffect } from 'react'
import { onAuthStateChanged } from 'firebase/auth'
import { auth } from './firebase'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Orders from './pages/Orders'
import Customers from './pages/Customers'
import Menu from './pages/Menu'
import Reports from './pages/Reports'
import Settings from './pages/Settings'
import Chats from './pages/Chats'

const ADMIN_EMAIL = 'chechiputtukadai@gmail.com'
const ADMIN_PHONE = '+917358888437'

function isAdmin(user) {
  if (!user) return false
  if (user.email === ADMIN_EMAIL) return true
  if (user.phoneNumber === ADMIN_PHONE) return true
  return false
}

function ProtectedRoute({ user, children }) {
  if (user === undefined) {
    return (
      <div className="min-h-screen bg-cream flex items-center justify-center">
        <div className="w-8 h-8 border-4 border-maroon border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }
  if (!user || !isAdmin(user)) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  const [user, setUser] = useState(undefined)

  useEffect(() => {
    return onAuthStateChanged(auth, (u) => setUser(u))
  }, [])

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={
          user && isAdmin(user) ? <Navigate to="/" replace /> : <Login />
        } />
        <Route path="/" element={
          <ProtectedRoute user={user}>
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
  )
}
