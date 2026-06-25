import { useState } from 'react'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from '../firebase'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await signInWithEmailAndPassword(auth, email, password)
    } catch (err) {
      setError('Invalid email or password. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex">
      {/* Left brand panel */}
      <div className="hidden lg:flex flex-col justify-center items-center w-1/2 bg-maroon-deep px-12">
        <div className="text-center">
          <div className="w-20 h-20 rounded-2xl bg-white/15 flex items-center justify-center text-4xl mx-auto mb-6">
            🍽️
          </div>
          <h1 className="font-display text-4xl font-bold text-white mb-3">
            Chechi Puttu Kadai
          </h1>
          <p className="text-white/60 text-lg leading-relaxed">
            Admin Dashboard — manage orders,<br />
            menu, customers & reports.
          </p>
          <div className="mt-10 grid grid-cols-3 gap-4 text-center">
            {[['Orders', '🧾'], ['Customers', '👥'], ['Reports', '📊']].map(([l, i]) => (
              <div key={l} className="bg-white/10 rounded-xl p-4">
                <p className="text-2xl mb-1">{i}</p>
                <p className="text-xs text-white/60 font-semibold">{l}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Right login form */}
      <div className="flex-1 flex items-center justify-center bg-cream px-6">
        <div className="w-full max-w-md">
          {/* Mobile logo */}
          <div className="text-center mb-8 lg:hidden">
            <div className="w-14 h-14 rounded-2xl bg-maroon flex items-center justify-center text-2xl mx-auto mb-3">
              🍽️
            </div>
            <h1 className="font-display text-2xl font-bold text-maroon-deep">Chechi Puttu Kadai</h1>
          </div>

          <div className="bg-white rounded-2xl border border-cream-border shadow-sm p-8">
            <h2 className="font-display text-2xl font-bold text-maroon-deep mb-1">Welcome back</h2>
            <p className="text-sm text-gray-500 mb-7">Sign in to your admin account</p>

            <form onSubmit={handleSubmit} className="space-y-5">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">Email</label>
                <input
                  type="email"
                  className="input"
                  placeholder="chechiputtukadai@gmail.com"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  required
                  autoComplete="email"
                />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">Password</label>
                <input
                  type="password"
                  className="input"
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                />
              </div>

              {error && (
                <div className="bg-red-50 border border-red-200 text-red-700 text-sm rounded-xl px-4 py-3">
                  {error}
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="btn-primary w-full py-3 flex items-center justify-center gap-2"
              >
                {loading ? (
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : null}
                {loading ? 'Signing in…' : 'Sign in'}
              </button>
            </form>
          </div>

          <p className="text-center text-xs text-gray-400 mt-6">
            Chechi Puttu Kadai Admin Panel · Access restricted
          </p>
        </div>
      </div>
    </div>
  )
}
