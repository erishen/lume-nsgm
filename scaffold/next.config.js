const path = require('path')

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  webpack: (config) => {
    config.resolve.alias['@'] = path.join(__dirname, 'client')
    return config
  },
}

module.exports = nextConfig
