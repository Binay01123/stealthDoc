import React from 'react';
import Head from '@docusaurus/Head';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import {useDoc} from '@docusaurus/plugin-content-docs/client';

export default function VideoStructuredData({
  videoId,
  uploadDate,
  duration,
}) {
  const {siteConfig} = useDocusaurusContext();
  const {contentTitle, frontMatter, metadata} = useDoc();
  const permalink = metadata.permalink.endsWith('/')
    ? metadata.permalink
    : `${metadata.permalink}/`;
  const structuredData = {
    '@context': 'https://schema.org',
    '@type': 'VideoObject',
    name: frontMatter.title ?? contentTitle,
    description: frontMatter.description,
    thumbnailUrl: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    uploadDate,
    duration,
    embedUrl: `https://www.youtube.com/embed/${videoId}`,
    url: new URL(permalink, siteConfig.url).href,
  };

  return (
    <Head>
      <script type="application/ld+json">
        {JSON.stringify(structuredData)}
      </script>
    </Head>
  );
}
