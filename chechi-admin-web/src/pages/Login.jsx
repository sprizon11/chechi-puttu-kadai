import { useState } from 'react'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from '../firebase'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
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
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    className="input pr-11"
                    placeholder="••••••••"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    required
                    autoComplete="current-password"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(v => !v)}
                    className="absolute inset-y-0 right-0 px-3 flex items-center text-gray-400 hover:text-maroon-deep transition-colors"
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                    title={showPassword ? 'Hide password' : 'Show password'}
                  >
                    {showPassword ? (
                      /* eye with a slash — password is visible, click to hide */
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
                        stroke="currentColor" strokeWidth="1.8"
                        strokeLinecap="round" strokeLinejoin="round">
                        <path d="M10.6 10.6a2 2 0 002.8 2.8" />
                        <path d="M16.7 16.7A9.9 9.9 0 0112 18c-5 0-9.3-3.6-10-6 .4-1.3 1.7-3 3.6-4.3" />
                        <path d="M9.9 5.2A10.6 10.6 0 0112 5c5 0 9.3 3.6 10 6-.4 1.2-1.5 2.7-3.1 4" />
                        <path d="M3 3l18 18" />
                      </svg>
                    ) : (
                      /* plain eye — password is hidden, click to show */
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
                        stroke="currentColor" strokeWidth="1.8"
                        strokeLinecap="round" strokeLinejoin="round">
                        <path d="M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6-10-6-10-6z" />
                        <circle cx="12" cy="12" r="2.6" />
                      </svg>
                    )}
                  </button>
                </div>
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
