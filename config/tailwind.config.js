const defaultTheme = require('tailwindcss/defaultTheme')

// QPDM Design System Color Palette (from Figma)
const qpdmColors = {
  // Tech Blue Scale (Primary)
  'tech-blue': {
    1: '#E6F7FF',
    2: '#BAE7FF',
    3: '#91D5FF',
    4: '#69C0FF',
    5: '#40A9FF',
    6: '#1890FF',
    7: '#0878F2',
    8: '#006DCB',
    9: '#0262B4',
    10: '#005197',
  },

  // Polar Green Scale (Success)
  'polar-green': {
    1: '#EBF9ED',
    2: '#D9F7BE',
    3: '#B7EB8F',
    4: '#95DE64',
    5: '#73D13D',
    6: '#52C41A',
    7: '#389E0D',
    8: '#237804',
    9: '#135200',
    10: '#092B00',
  },

  // Dust Red Scale (Error)
  'dust-red': {
    1: '#FFEBEA',
    2: '#FFCCC7',
    3: '#FFA39E',
    4: '#FF7875',
    5: '#FF4D4F',
    6: '#F5222D',
    7: '#CF1322',
    8: '#A8071A',
    9: '#820014',
    10: '#5C0011',
  },

  // Warm Orange Scale (Warning)
  'warm-orange': {
    1: '#FFF2E7',
    2: '#FFE6CF',
    3: '#FFD4A1',
    4: '#FFC887',
    5: '#FFBF75',
    6: '#FFB660',
    7: '#FFAF52',
    8: '#D97500',
    9: '#A55900',
    10: '#7E4400',
  },

  // Bright Yellow (accent)
  'bright-yellow': {
    1: '#FFF6E7',
    6: '#FFD400',
  },

  // Geek Blue Scale (for login role badges)
  'geek-blue': {
    1: '#F0F5FF',
    2: '#D6E4FF',
    3: '#ADC6FF',
    4: '#85A5FF',
    5: '#597EF7',
    6: '#2F54EB',
    7: '#1D39C4',
    8: '#10239E',
    9: '#061178',
    10: '#030852',
  },

  // Sunrise Yellow Scale (for pending states)
  'sunrise-yellow': {
    1: '#FEFFE6',
    2: '#FFFFB8',
    3: '#FFFB8F',
    4: '#FFF566',
    5: '#FFEC3D',
    6: '#FADB14',
    7: '#D4B106',
    8: '#AD8B00',
    9: '#876800',
    10: '#614700',
  },

  // Neutral - Black Scale (for light backgrounds)
  'black': {
    DEFAULT: '#000000',  // Preserve bg-black/text-black
    2: '#FAFAFA',
    4: '#F5F5F5',
    6: '#F0F0F0',
    8: '#E8E8E8',
    15: '#D9D9D9',
    25: '#BFBFBF',
    45: '#8C8C8C',
    85: '#262626',
  },

  // Neutral - White Scale (for dark backgrounds)
  'white': {
    DEFAULT: '#FFFFFF',  // Preserve bg-white/text-white
    4: '#1D1D1D',
    8: '#262626',
    12: '#303030',
    20: '#434343',
    45: '#7D7D7D',
    85: '#DBDBDB',
    100: '#FFFFFF',
  },

  // QCT Brand Color
  'qct-blue': '#005197',
}

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
      colors: {
        // Figma-named colors (for designer-developer collaboration)
        'tech-blue': qpdmColors['tech-blue'],
        'polar-green': qpdmColors['polar-green'],
        'dust-red': qpdmColors['dust-red'],
        'warm-orange': qpdmColors['warm-orange'],
        'bright-yellow': qpdmColors['bright-yellow'],
        'geek-blue': qpdmColors['geek-blue'],
        'sunrise-yellow': qpdmColors['sunrise-yellow'],
        'black': qpdmColors['black'],
        'white': qpdmColors['white'],
        'qct-blue': qpdmColors['qct-blue'],

        // Semantic aliases (for developer convenience)
        // These reference the Figma colors, not duplicate hex values
        'primary': qpdmColors['tech-blue'],
        'success': qpdmColors['polar-green'],
        'error': qpdmColors['dust-red'],
        'warning': qpdmColors['warm-orange'],
        'login': qpdmColors['geek-blue'],
        'pending': qpdmColors['sunrise-yellow'],
        // Neutral combines black scale values (used as semantic neutral for general UI)
        'neutral': qpdmColors['black'],
      },
    },
  },
  plugins: [
    // require('@tailwindcss/forms'),
    // require('@tailwindcss/typography'),
    // require('@tailwindcss/container-queries'),
  ]
}
