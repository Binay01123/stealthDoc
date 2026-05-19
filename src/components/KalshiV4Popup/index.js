import React, {useCallback, useEffect, useState} from 'react';
import WatchOnYouTubeButton from '@site/src/components/WatchOnYouTubeButton';
import popupPoster from '@site/static/img/kalshi-v4-popup.png';
import styles from './styles.module.css';

const videoUrl = 'https://youtu.be/48NJfddRVeE';

export default function KalshiV4Popup() {
  const [isVisible, setIsVisible] = useState(false);
  const [storageKey, setStorageKey] = useState('');

  useEffect(() => {
    const key = `kalshi-v4-popup:${window.location.pathname}`;
    setStorageKey(key);

    const storedState = window.sessionStorage.getItem(key);
    setIsVisible(storedState !== 'dismissed');
  }, []);

  const closeBanner = useCallback(() => {
    if (storageKey) {
      window.sessionStorage.setItem(storageKey, 'dismissed');
    }
    setIsVisible(false);
  }, [storageKey]);

  if (!isVisible) {
    return null;
  }

  return (
    <div className={styles.bannerShell}>
      <section
        aria-labelledby="kalshi-v4-popup-title"
        className={styles.banner}>
        <button
          aria-label="Close Kalshi Trading Bot v4.0 notice"
          className={styles.closeButton}
          onClick={closeBanner}
          type="button">
          x
        </button>
        <img
          alt="Kalshi Trading Bot version 4.0"
          className={styles.poster}
          src={popupPoster}
        />
        <div className={styles.content}>
          <div className={styles.eyebrow}>New walkthrough available</div>
          <h2 className={styles.title} id="kalshi-v4-popup-title">
            Kalshi Trading Bot v4.0 is out now
          </h2>
          <p className={styles.description}>
            Version 4 adds multi-agent execution and delta-aware entries for
            Kalshi 15 minute crypto markets.
          </p>
          <WatchOnYouTubeButton href={videoUrl} />
        </div>
      </section>
    </div>
  );
}
