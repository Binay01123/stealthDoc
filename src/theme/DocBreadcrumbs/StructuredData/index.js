import React from 'react';
import Head from '@docusaurus/Head';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';

function withTrailingSlash(href) {
  if (!href || href === '/' || href.endsWith('/')) {
    return href;
  }

  const hashIndex = href.indexOf('#');
  const hash = hashIndex >= 0 ? href.slice(hashIndex) : '';
  const withoutHash = hashIndex >= 0 ? href.slice(0, hashIndex) : href;
  const queryIndex = withoutHash.indexOf('?');
  const query = queryIndex >= 0 ? withoutHash.slice(queryIndex) : '';
  const pathname = queryIndex >= 0 ? withoutHash.slice(0, queryIndex) : withoutHash;

  if (!pathname || pathname.endsWith('/')) {
    return href;
  }

  return `${pathname}/${query}${hash}`;
}

export default function DocBreadcrumbsStructuredData({breadcrumbs}) {
  const {siteConfig} = useDocusaurusContext();
  const structuredData = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: breadcrumbs
      .filter((breadcrumb) => breadcrumb.href)
      .map((breadcrumb, index) => ({
        '@type': 'ListItem',
        position: index + 1,
        name: breadcrumb.label,
        item: `${siteConfig.url}${withTrailingSlash(breadcrumb.href)}`,
      })),
  };

  return (
    <Head>
      <script type="application/ld+json">
        {JSON.stringify(structuredData)}
      </script>
    </Head>
  );
}
