// @ts-check

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.

 @type {import('@docusaurus/plugin-content-docs').SidebarsConfig}
 */
const sidebars = {
  tutorialSidebar: [
    {
      type: 'category',
      label: 'YouTube Series',
      link: {
        type: 'generated-index',
        slug: '/youtube-code',
        title: 'YouTube Code Series',
        description:
          'Browse the ProcessOverProfit YouTube code series, including automated trading scripts, Kalshi bots, Polymarket bots, and Nightshark walkthroughs.',
      },
      items: [
        'youtube-code/video-1/video-1-mlma',
        'youtube-code/video-2/video-2-WicklessHeikenAshi',
        'youtube-code/video-3/video-3-SuperTrend',
        'youtube-code/video-4/video-4-mean-reversion',
        'youtube-code/video-5/video-5-mlma',
        'youtube-code/video-6/video-6-mlma',
        'youtube-code/video-7/video-7-mlma',
        'youtube-code/video-8/video-8-mlma',
        'youtube-code/video-9/video-9-kalshi-v3',
        'youtube-code/video-10/video-10-kalshi-v4',
        'youtube-code/video-11/video-11-kalshi-arbitrage',
        'youtube-code/video-12/video-12-kalshi-backtesting',
        'youtube-code/video-13/video-13-polymarket-crypto-bot',
        'youtube-code/video-14/video-14-kalshi-v5',
      ],
      collapsible: true,
      collapsed: false,
    },
  ],
};

export default sidebars;
