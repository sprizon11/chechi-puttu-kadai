import { useEffect, useState, useRef } from 'react'
import {
  collection, query, orderBy, limit, onSnapshot,
  doc, setDoc, addDoc, serverTimestamp, writeBatch
} from 'firebase/firestore'
import { db } from '../firebase'
import { format, formatDistanceToNow } from 'date-fns'

function readTime(t) {
  if (!t) return null
  if (t.toDate) return t.toDate()
  if (t.seconds) return new Date(t.seconds * 1000)
  return null
}

function timeAgo(t) {
  const d = readTime(t)
  if (!d) return ''
  return formatDistanceToNow(d, { addSuffix: true })
}

export default function Chats() {
  const [threads, setThreads]         = useState([])
  const [users, setUsers]             = useState([])
  const [selected, setSelected]       = useState(null)
  const [messages, setMessages]       = useState([])
  const [text, setText]               = useState('')
  const [sending, setSending]         = useState(false)
  const [loadingThreads, setLoadingThreads] = useState(true)
  const [showBroadcast, setShowBroadcast]   = useState(false)
  const [broadcastText, setBroadcastText]   = useState('')
  const [broadcasting, setBroadcasting]     = useState(false)
  const [broadcastDone, setBroadcastDone]   = useState(false)
  const [search, setSearch]           = useState('')
  const scrollRef  = useRef(null)
  const inputRef   = useRef(null)

  // Live thread list
  useEffect(() => {
    const q = query(collection(db, 'support_inbox'), orderBy('last_at', 'desc'), limit(300))
    return onSnapshot(q, snap => {
      setThreads(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoadingThreads(false)
    }, () => setLoadingThreads(false))
  }, [])

  // Users for display names
  useEffect(() => {
    const q = query(collection(db, 'users'), limit(500))
    return onSnapshot(q, snap => setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() }))))
  }, [])

  // Messages for selected thread
  useEffect(() => {
    if (!selected) { setMessages([]); return }
    const q = query(
      collection(db, 'support_inbox', selected, 'messages'),
      orderBy('created_at', 'asc'),
      limit(300)
    )
    return onSnapshot(q, snap => setMessages(snap.docs.map(d => ({ id: d.id, ...d.data() }))))
  }, [selected])

  // Auto scroll to bottom when messages change
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
  }, [messages])

  // Mark thread read when opened
  useEffect(() => {
    if (!selected) return
    setDoc(doc(db, 'support_inbox', selected), {
      unread_customer_to_admin: 0,
      updated_at: serverTimestamp(),
    }, { merge: true }).catch(() => {})
  }, [selected])

  const getUserName = uid => {
    const t = threads.find(t => t.id === uid)
    if (t?.customer_name) return t.customer_name
    const u = users.find(u => u.id === uid)
    return u?.displayName || 'Customer'
  }

  const filtered = threads.filter(t => {
    if (!search) return true
    const q = search.toLowerCase()
    const name = (t.customer_name || getUserName(t.id) || '').toLowerCase()
    const mob  = (t.customer_mobile || '').toLowerCase()
    const last = (t.last_message || '').toLowerCase()
    return name.includes(q) || mob.includes(q) || last.includes(q)
  })

  const totalUnread = threads.reduce((s, t) => s + (t.unread_customer_to_admin || 0), 0)

  async function sendMessage(e) {
    e?.preventDefault()
    const msg = text.trim()
    if (!selected || !msg || sending) return
    setSending(true)
    setText('')
    try {
      await addDoc(collection(db, 'support_inbox', selected, 'messages'), {
        text: msg,
        sender: 'admin',
        created_at: serverTimestamp(),
      })
      await setDoc(doc(db, 'support_inbox', selected), {
        last_message: msg,
        last_sender: 'admin',
        last_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }, { merge: true })
      inputRef.current?.focus()
    } finally {
      setSending(false)
    }
  }

  async function sendBroadcast() {
    const msg = broadcastText.trim()
    if (!msg || broadcasting) return
    if (!confirm(`Send this message to all ${users.length} customers?\n\n"${msg}"`)) return
    setBroadcasting(true)
    try {
      // chunk into batches of 100 (2 writes per user = 200 ops, safely under 500 limit)
      const chunks = []
      for (let i = 0; i < users.length; i += 100) chunks.push(users.slice(i, i + 100))
      for (const chunk of chunks) {
        const batch = writeBatch(db)
        for (const u of chunk) {
          const threadRef = doc(db, 'support_inbox', u.id)
          const msgRef    = doc(collection(db, 'support_inbox', u.id, 'messages'))
          batch.set(msgRef, {
            text: msg,
            sender: 'admin',
            broadcast: true,
            created_at: serverTimestamp(),
          })
          batch.set(threadRef, {
            customer_uid: u.id,
            customer_name: u.displayName || 'Customer',
            customer_mobile: u.mobile || u.authPhone || '',
            last_message: msg,
            last_sender: 'admin',
            last_at: serverTimestamp(),
            updated_at: serverTimestamp(),
            unread_customer_to_admin: 0,
          }, { merge: true })
        }
        await batch.commit()
      }
      setBroadcastText('')
      setShowBroadcast(false)
      setBroadcastDone(true)
      setTimeout(() => setBroadcastDone(false), 4000)
    } catch (e) {
      alert(`Broadcast failed: ${e.message}`)
    } finally {
      setBroadcasting(false)
    }
  }

  const selectedThread = threads.find(t => t.id === selected)
  const selectedName   = selected ? getUserName(selected) : ''

  return (
    <div className="flex gap-0 h-[calc(100vh-88px)] -m-6 overflow-hidden">

      {/* ── Thread list ─────────────────────────────────────────── */}
      <div className={`flex flex-col bg-white border-r border-cream-border shrink-0 ${selected ? 'hidden lg:flex w-80' : 'flex w-full lg:w-80'}`}>

        {/* Header */}
        <div className="px-4 pt-5 pb-3 border-b border-cream-border">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <h1 className="font-display font-bold text-xl text-maroon-deep">Support Chat</h1>
              {totalUnread > 0 && (
                <span className="bg-red-500 text-white text-xs font-bold rounded-full px-1.5 py-0.5 min-w-[18px] text-center">
                  {totalUnread}
                </span>
              )}
            </div>
            <button
              onClick={() => setShowBroadcast(true)}
              className="flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-xl bg-maroon text-white hover:bg-maroon-deep transition-colors"
              title="Broadcast to all customers"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5.882V19.24a1.76 1.76 0 01-3.417.592l-2.147-6.15M18 13a3 3 0 100-6M5.436 13.683A4.001 4.001 0 017 6h1.832c4.1 0 7.625-1.234 9.168-3v14c-1.543-1.766-5.067-3-9.168-3H7a3.988 3.988 0 01-1.564-.317z" />
              </svg>
              Broadcast
            </button>
          </div>
          <input
            className="input text-sm"
            placeholder="Search chats..."
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
          {broadcastDone && (
            <p className="text-xs text-green-600 font-semibold mt-2 text-center">
              Broadcast sent to {users.length} customers!
            </p>
          )}
        </div>

        {/* Thread list */}
        <div className="flex-1 overflow-y-auto">
          {loadingThreads ? (
            <div className="flex items-center justify-center h-32">
              <div className="w-6 h-6 border-2 border-maroon border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-48 gap-2 text-gray-400">
              <svg xmlns="http://www.w3.org/2000/svg" className="w-10 h-10 opacity-30" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
              <p className="text-sm">No conversations yet</p>
            </div>
          ) : (
            filtered.map(t => {
              const unread = t.unread_customer_to_admin || 0
              const name   = t.customer_name || getUserName(t.id) || 'Customer'
              const initials = name.charAt(0).toUpperCase()
              const lastTime = readTime(t.last_at)
              const isSelected = t.id === selected
              return (
                <button
                  key={t.id}
                  onClick={() => setSelected(t.id)}
                  className={`w-full flex items-start gap-3 px-4 py-3.5 border-b border-cream-border/60 text-left transition-colors ${
                    isSelected ? 'bg-cream' : 'hover:bg-cream/60'
                  }`}
                >
                  <div className="relative shrink-0">
                    <div className="w-10 h-10 rounded-full bg-maroon/10 flex items-center justify-center text-maroon font-bold text-sm">
                      {initials}
                    </div>
                    {unread > 0 && (
                      <span className="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-bold rounded-full w-4.5 h-4.5 flex items-center justify-center min-w-[18px] px-1">
                        {unread}
                      </span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-baseline justify-between gap-1">
                      <p className={`text-sm truncate ${unread > 0 ? 'font-bold text-gray-900' : 'font-semibold text-gray-800'}`}>
                        {name}
                      </p>
                      {lastTime && (
                        <p className="text-[10px] text-gray-400 shrink-0">{timeAgo(t.last_at)}</p>
                      )}
                    </div>
                    {t.customer_mobile && (
                      <p className="text-[11px] text-gray-400 font-mono">{t.customer_mobile}</p>
                    )}
                    <p className={`text-xs truncate mt-0.5 ${unread > 0 ? 'text-gray-700 font-semibold' : 'text-gray-400'}`}>
                      {t.last_sender === 'admin' ? 'You: ' : ''}{t.last_message || ''}
                    </p>
                  </div>
                </button>
              )
            })
          )}
        </div>
      </div>

      {/* ── Chat panel ─────────────────────────────────────────── */}
      <div className={`flex-1 flex flex-col bg-[#FDF8F5] min-w-0 ${!selected ? 'hidden lg:flex' : 'flex'}`}>
        {!selected ? (
          <div className="flex-1 flex flex-col items-center justify-center gap-3 text-gray-400">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-16 h-16 opacity-20" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
            <p className="text-base font-semibold">Select a conversation</p>
            <p className="text-sm">Choose a chat from the list to start replying</p>
          </div>
        ) : (
          <>
            {/* Chat header */}
            <div className="flex items-center gap-3 px-5 py-4 bg-white border-b border-cream-border shrink-0">
              <button
                className="lg:hidden p-2 -ml-1 rounded-lg hover:bg-cream transition-colors"
                onClick={() => setSelected(null)}
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                </svg>
              </button>
              <div className="w-9 h-9 rounded-full bg-maroon/10 flex items-center justify-center text-maroon font-bold shrink-0">
                {selectedName.charAt(0).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-gray-900 text-sm">{selectedName}</p>
                {selectedThread?.customer_mobile && (
                  <p className="text-xs text-gray-400 font-mono">{selectedThread.customer_mobile}</p>
                )}
              </div>
            </div>

            {/* Messages */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-4 space-y-2">
              {messages.length === 0 ? (
                <div className="flex items-center justify-center h-full text-gray-400 text-sm">
                  No messages yet
                </div>
              ) : (
                messages.map(m => {
                  const isAdmin = m.sender === 'admin'
                  const t = readTime(m.created_at)
                  return (
                    <div key={m.id} className={`flex ${isAdmin ? 'justify-end' : 'justify-start'}`}>
                      <div className={`max-w-[72%] rounded-2xl px-4 py-2.5 ${
                        isAdmin
                          ? 'bg-maroon text-white rounded-br-sm'
                          : 'bg-white text-gray-800 rounded-bl-sm shadow-sm border border-cream-border'
                      }`}>
                        {m.broadcast && (
                          <p className={`text-[10px] font-bold mb-1 uppercase tracking-wide ${isAdmin ? 'text-white/60' : 'text-maroon'}`}>
                            Broadcast
                          </p>
                        )}
                        <p className="text-sm leading-relaxed">{m.text}</p>
                        {t && (
                          <p className={`text-[10px] mt-1 ${isAdmin ? 'text-white/50' : 'text-gray-400'}`}>
                            {format(t, 'h:mm a')}
                          </p>
                        )}
                      </div>
                    </div>
                  )
                })
              )}
            </div>

            {/* Reply input */}
            <form onSubmit={sendMessage} className="flex items-end gap-2 px-4 py-3 bg-white border-t border-cream-border shrink-0">
              <textarea
                ref={inputRef}
                className="flex-1 input resize-none text-sm py-2.5"
                rows={1}
                placeholder="Type a reply..."
                value={text}
                onChange={e => setText(e.target.value)}
                onKeyDown={e => {
                  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() }
                }}
                style={{ minHeight: 44, maxHeight: 120 }}
              />
              <button
                type="submit"
                disabled={!text.trim() || sending}
                className="w-11 h-11 rounded-xl bg-maroon text-white flex items-center justify-center hover:bg-maroon-deep transition-colors disabled:opacity-40 shrink-0"
              >
                {sending
                  ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  : <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M3.478 2.405a.75.75 0 00-.926.94l2.432 7.905H13.5a.75.75 0 010 1.5H4.984l-2.432 7.905a.75.75 0 00.926.94 60.519 60.519 0 0018.445-8.986.75.75 0 000-1.218A60.517 60.517 0 003.478 2.405z" />
                    </svg>
                }
              </button>
            </form>
          </>
        )}
      </div>

      {/* ── Broadcast modal ─────────────────────────────────────── */}
      {showBroadcast && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-md p-6">
            <h3 className="font-display font-bold text-xl text-maroon-deep mb-1">Broadcast Message</h3>
            <p className="text-sm text-gray-500 mb-4">
              This message will be sent to all {users.length} customers in their support chat.
            </p>
            <textarea
              className="input w-full resize-none text-sm"
              rows={4}
              placeholder="Type your offer, announcement, or update..."
              value={broadcastText}
              onChange={e => setBroadcastText(e.target.value)}
              autoFocus
            />
            <div className="flex gap-3 mt-4">
              <button
                onClick={() => { setShowBroadcast(false); setBroadcastText('') }}
                className="flex-1 py-2.5 rounded-xl border border-cream-border text-sm font-semibold text-gray-600 hover:bg-cream transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={sendBroadcast}
                disabled={!broadcastText.trim() || broadcasting}
                className="flex-1 py-2.5 rounded-xl bg-maroon text-white text-sm font-bold hover:bg-maroon-deep transition-colors disabled:opacity-50"
              >
                {broadcasting ? 'Sending...' : `Send to ${users.length} customers`}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
