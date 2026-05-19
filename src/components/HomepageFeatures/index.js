import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Automated Trading',
    image: require('@site/static/img/undraw_docusaurus_mountain.png').default,
    link: '/docs/youtube-code/',
    description: (
      <>
        Build and deploy automated trading strategies that execute trades 24/7
        without manual intervention. Access code from our YouTube series.
      </>
    ),
  },
  {
    title: 'Process Over Profit',
    image: require('@site/static/img/undraw_docusaurus_tree.png').default,
    link: 'https://www.youtube.com/@ProcessOverProfitHQ',
    description: (
      <>
        Focus on building robust trading processes and systems. Consistent,
        repeatable processes lead to sustainable profits in the long run.
      </>
    ),
  },
  {
    title: 'Advanced Analytics',
    image: require('@site/static/img/undraw_docusaurus_react.png').default,
    description: (
      <>
        Monitor performance, analyze trades, and optimize strategies with
        comprehensive analytics and real-time insights into your trading systems.
      </>
    ),
  },
];

function Feature({image, title, description, isWide, link}) {
  const CardContent = () => (
    <div className={styles.featureCard}>
      <div className="text--center">
        <img 
          src={image} 
          className={isWide ? styles.featureSvgWide : styles.featureSvg} 
          role="img" 
          alt={title} 
        />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3" className={styles.featureTitle}>{title}</Heading>
        <p className={styles.featureDescription}>{description}</p>
      </div>
    </div>
  );

  return (
    <div className={clsx('col col--4')}>
      {link ? (
        <Link to={link} className={styles.featureLink}>
          <CardContent />
        </Link>
      ) : (
        <CardContent />
      )}
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} isWide={idx === 1} />
          ))}
        </div>
      </div>
    </section>
  );
}
