import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

import Heading from '@theme/Heading';
import styles from './index.module.css';
import Shuffle from '@site/src/components/Shuffle';
import LetterGlitch from '@site/src/components/LetterGlitch';
import DecryptedText from '@site/src/components/DecryptedText';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  const titleWords = siteConfig.title.replace(/([A-Z])/g, ' $1').trim();
  
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className={styles.glitchBackground}>
        <LetterGlitch
          glitchSpeed={50}
          centerVignette={true}
          outerVignette={false}
          smooth={true}
          glitchColors={['#2b4539', '#61dca3', '#61b3dc']}
        />
      </div>
      <div className={clsx('container', styles.heroContent)}>
        <div className={styles.heroTitle}>
          <Shuffle 
            text={titleWords}
            shuffleDirection="right"
            duration={0.35}
            animationMode="evenodd"
            shuffleTimes={1}
            ease="power3.out"
            stagger={0.03}
            threshold={0.1}
            triggerOnce={true}
            triggerOnHover={true}
            respectReducedMotion={true}
          />
        </div>
        <p className="hero__subtitle">
          <DecryptedText
            text={siteConfig.tagline}
            animateOn="view"
            revealDirection="center"
            className={styles.decryptedSubtitle}
            encryptedClassName={styles.decryptedSubtitle}
          />
        </p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg"
            href="https://www.youtube.com/@ProcessOverProfitHQ"
            target="_blank"
            rel="noopener noreferrer"
            style={{marginRight: '1rem'}}>
            <img 
              src="/img/youtube-icon.svg" 
              alt="YouTube" 
              style={{width: '24px', height: '24px', marginRight: '8px', verticalAlign: 'middle'}} 
            />
            Watch on YouTube
          </Link>
          <Link
            className={clsx('button button--primary button--lg', styles.nightsharkButton)}
            href="https://nightshark.io"
            target="_blank"
            rel="noopener noreferrer">
            <img 
              src="/img/nightshark-logo.png" 
              alt="Nightshark" 
              style={{width: '24px', height: '24px', marginRight: '8px', verticalAlign: 'middle'}} 
            />
            Download Nightshark
          </Link>
        </div>
      </div>
    </header>
  );
}

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={`${siteConfig.title} - Trading Automation Platform`}
      description="Automate your trading strategies with ProcessOverProfit. Build, deploy, and monitor automated trading systems.">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
