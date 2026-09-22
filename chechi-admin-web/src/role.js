import { createContext, useContext } from 'react'
import { doc, getDoc } from 'firebase/firestore'
import { db } from './firebase'

export const ADMIN_EMAIL = 'chechiputtukadai@gmail.com'
export const ADMIN_PHONE = '+917358888437'

/**
 * Works out who is signed in: 'admin', 'staff', or null (no access).
 *
 * Staff accounts are made by the adminCreateStaff Cloud Function, which sets
 * the { staff: true } claim and writes staff/{uid}. Both must be present —
 * the same test the Firestore rules apply — so a removed staff member is
 * turned away here as well as by the rules.
 */
export async function resolveRole(user) {
  if (!user) return { role: null, staff: null }
  if (user.email?.toLowerCase() === ADMIN_EMAIL || user.phoneNumber === ADMIN_PHONE) {
    return { role: 'admin', staff: null }
  }
  const { claims } = await user.getIdTokenResult()
  if (claims.admin === true) return { role: 'admin', staff: null }
  if (claims.staff === true) {
    const snap = await getDoc(doc(db, 'staff', user.uid)).catch(() => null)
    if (snap?.exists()) return { role: 'staff', staff: snap.data() }
  }
  return { role: null, staff: null }
}

export const RoleContext = createContext({ role: null, staff: null })

/** { role, staff, isAdmin } for the signed-in user. */
export function useRole() {
  const ctx = useContext(RoleContext)
  return { ...ctx, isAdmin: ctx.role === 'admin' }
}
