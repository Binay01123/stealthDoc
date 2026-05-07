import React, {useCallback, useEffect, useState} from 'react';
import WatchOnYouTubeButton from '@site/src/components/WatchOnYouTubeButton';
import styles from './styles.module.css';

const videoUrl = 'https://youtu.be/48NJfddRVeE';

export default function KalshiV4Popup() {
  const [isVisible, setIsVisible] = useState(false);
  const [storageKey, setStorageKey] = useState('');

  useEffect(() => {
    const key = `kalshi-v4-popup:${window.location.pathname}`;
    setStorageKey(key);

    if (window.sessionStorage.getItem(key) !== 'dismissed') {
      setIsVisible(true);
    }
  }, []);

  const closePopup = useCallback(() => {
    if (storageKey) {
      window.sessionStorage.setItem(storageKey, 'dismissed');
    }
    setIsVisible(false);
  }, [storageKey]);

  if (!isVisible) {
    return null;
  }

  return (
    <div className={styles.backdrop} role="presentation" onClick={closePopup}>
      <section
        aria-labelledby="kalshi-v4-popup-title"
        aria-modal="true"
        className={styles.popup}
        onClick={(event) => event.stopPropagation()}
        role="dialog">
        <button
          aria-label="Close popup"
          className={styles.closeButton}
          onClick={closePopup}
          type="button">
          x
        </button>
        <img
          alt="Kalshi Trading Bot version 4.0"
          className={styles.poster}
          src="/img/kalshi-v4-popup.png"
        />
        <div className={styles.content}>
          <div className={styles.eyebrow}>New walkthrough available</div>
          <h2 className={styles.title} id="kalshi-v4-popup-title">
            Kalshi Trading Bot v4.0 is live
          </h2>
          <p className={styles.description}>
            Version 4 adds multi-agent execution and delta-aware entries for
            Kalshi 15 minute crypto markets. Watch the update before running
            the older bot versions.
          </p>
          <WatchOnYouTubeButton href={videoUrl} />
        </div>
      </section>
    </div>
  );
}
