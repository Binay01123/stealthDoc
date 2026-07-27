import React, {useEffect, useRef, useState} from 'react';
import styles from './styles.module.css';

function CopyIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <rect x="9" y="9" width="11" height="11" rx="2" />
      <path d="M15 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h3" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="m5 12.5 4.25 4.25L19 7" />
    </svg>
  );
}

function copyWithFallback(value) {
  const textarea = document.createElement('textarea');
  textarea.value = value;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  const copied = document.execCommand('copy');
  textarea.remove();

  if (!copied) {
    throw new Error('Copy command failed');
  }
}

export default function CredentialCopyList({items}) {
  const [copyStatus, setCopyStatus] = useState({index: null, state: 'idle'});
  const resetTimer = useRef(null);

  useEffect(
    () => () => {
      window.clearTimeout(resetTimer.current);
    },
    [],
  );

  async function copyCredential(value, index) {
    window.clearTimeout(resetTimer.current);

    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(value);
      } else {
        copyWithFallback(value);
      }

      setCopyStatus({index, state: 'copied'});
    } catch {
      setCopyStatus({index, state: 'failed'});
    }

    resetTimer.current = window.setTimeout(
      () => setCopyStatus({index: null, state: 'idle'}),
      1800,
    );
  }

  return (
    <div
      className={styles.credentialBlock}
      role="group"
      aria-label="Polymarket credential filenames">
      {items.map(({label, value}, index) => {
        const currentState =
          copyStatus.index === index ? copyStatus.state : 'idle';
        const buttonText =
          currentState === 'copied'
            ? 'Copied'
            : currentState === 'failed'
              ? 'Retry'
              : 'Copy';

        return (
          <div className={styles.credentialRow} key={`${label}-${value}`}>
            <span className={styles.label}>{label}</span>
            <code className={styles.value}>{value}</code>
            <button
              className={`${styles.copyButton} ${
                currentState === 'copied' ? styles.copyButtonCopied : ''
              }`}
              type="button"
              onClick={() => copyCredential(value, index)}
              aria-label={
                currentState === 'copied'
                  ? `${label} copied`
                  : `Copy ${label}: ${value}`
              }>
              <span>{buttonText}</span>
              {currentState === 'copied' ? <CheckIcon /> : <CopyIcon />}
            </button>
          </div>
        );
      })}
    </div>
  );
}
