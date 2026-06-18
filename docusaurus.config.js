// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import {themes as prismThemes} from 'prism-react-renderer';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'ProcessOverProfit',
  tagline: 'Building systematic approaches and proven processes over chasing profits',
  favicon: 'img/logo.png',
  scripts: [
    {
      src: 'https://static.cloudflareinsights.com/beacon.min.js',
      defer: true,
      'data-cf-beacon': '{"token": "7e3d66bb4f914cfeac0f963859577d7c"}',
    },
  ],

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // Set the production url of your site here
  url: 'https://code.processoverprofit.blog',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/',
  trailingSlash: true,

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'Binay01123', // Usually your GitHub org/user name.
  projectName: 'stealthDoc', // Usually your repo name.

  onBrokenLinks: 'throw',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
        },
        blog: false,
        sitemap: {
          lastmod: 'date',
          ignorePatterns: ['/playground/**'],
          createSitemapItems: async (params) => {
            const items = await params.defaultCreateSitemapItems(params);
            const videoPagePattern =
              /^\/docs\/youtube-code\/video-(?:[1-9]|1[0-2])-[^/]+\/$/;

            const prioritizedItems = items.map((item) => {
              const pathname = new URL(item.url).pathname;

              if (videoPagePattern.test(pathname)) {
                return {...item, priority: 1};
              }

              if (pathname === '/docs/youtube-code/') {
                return {...item, priority: 0.7};
              }

              return {...item, priority: 0.3};
            });

            return prioritizedItems.sort(
              (left, right) => (right.priority ?? 0) - (left.priority ?? 0),
            );
          },
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  plugins: [
    [
      '@docusaurus/plugin-client-redirects',
      {
        redirects: [
          {
            from: '/docs/intro',
            to: '/docs/youtube-code',
          },
          {
            from: '/docs/youtube-code/video-1',
            to: '/docs/youtube-code/video-1-mlma',
          },
        ],
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your project's social card
      image: 'img/logo.png',
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: true,
        respectPrefersColorScheme: false,
      },
      navbar: {
        title: 'ProcessOverProfit',
        logo: {
          alt: 'ProcessOverProfit Logo',
          src: 'img/logo.png',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'tutorialSidebar',
            position: 'left',
            label: 'YouTube Code',
          },
          {
            type: 'custom-discord',
            position: 'right',
            href: 'https://discord.gg/JKa2njzaQD',
          },
        ],
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

export default config;
