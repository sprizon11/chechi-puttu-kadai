/**
 * Shared Framer Motion variants.
 *
 * Kept in one place so every page moves the same way — a page that eases
 * differently from its neighbour reads as a bug, not as personality.
 *
 * The easing is a single soft-landing curve: quick to start, slow to settle.
 */

export const EASE = [0.22, 1, 0.36, 1]

/** Wraps a page. Children with `riseItem` stagger in beneath it. */
export const pageStagger = {
  hidden: {},
  show: {
    transition: { staggerChildren: 0.055, delayChildren: 0.04 },
  },
}

/** Default entrance: up and in. Use for cards, rows, sections. */
export const riseItem = {
  hidden: { opacity: 0, y: 18 },
  show: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.5, ease: EASE },
  },
}

/** For tiles that should feel like they surface rather than slide. */
export const popItem = {
  hidden: { opacity: 0, y: 14, scale: 0.97 },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: { duration: 0.45, ease: EASE },
  },
}

/** Route change: the outgoing page leaves before the new one arrives. */
export const pageTransition = {
  initial: { opacity: 0, y: 12 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.35, ease: EASE } },
  exit: { opacity: 0, y: -8, transition: { duration: 0.2, ease: 'easeIn' } },
}

/** Hover/press feedback for anything clickable that is not a button. */
export const tapScale = {
  whileHover: { y: -2 },
  whileTap: { scale: 0.985 },
  transition: { duration: 0.18, ease: EASE },
}
