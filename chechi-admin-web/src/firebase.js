import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: 'AIzaSyBjWBkl5uWzv32ktRGe4cRjGOPCqq-yY2k',
  authDomain: 'chechi-puttu-kadai.firebaseapp.com',
  projectId: 'chechi-puttu-kadai',
  storageBucket: 'chechi-puttu-kadai.firebasestorage.app',
  messagingSenderId: '316102307451',
  appId: '1:316102307451:web:fd05bda542f43bb9633cde',
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app, 'default')
