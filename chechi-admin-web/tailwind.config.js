/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        maroon: {
          DEFAULT: '#7C1D1B',
          deep: '#5D1F1A',
          light: '#9E2E2B',
        },
        cream: {
          DEFAULT: '#FFF6ED',
          card: '#FFFCF8',
          border: '#E4D7C7',
        },
        brand: {
          orange: '#EA7A2C',
          gold: '#C9A227',
          accent: '#E85D3F',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Georgia', 'serif'],
      },
    },
  },
  plugins: [],
}
