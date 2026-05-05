import React, {useCallback, useEffect, useRef, useState} from 'react';
import clsx from 'clsx';
import {translate} from '@docusaurus/Translate';
import {useCodeBlockContext} from '@docusaurus/theme-common/internal';
import Button from '@theme/CodeBlock/Buttons/Button';
import IconCopy from '@theme/Icon/Copy';
import IconSuccess from '@theme/Icon/Success';
import styles from './styles.module.css';

const copiedDelay = 1000;

function title() {
  return translate({
    id: 'theme.CodeBlock.copy',
    message: 'Copy',
    description: 'The copy button label on code blocks',
  });
}

function ariaLabel(copyState) {
  if (copyState === 'copying') {
    return translate({
      id: 'theme.CodeBlock.copying',
      message: 'Copying code to clipboard',
      description: 'The ARIA label while a code block is being copied',
    });
  }

  if (copyState === 'copied') {
    return translate({
      id: 'theme.CodeBlock.copied',
      message: 'Copied',
      description: 'The copied button label on code blocks',
    });
  }

  return translate({
    id: 'theme.CodeBlock.copyButtonAriaLabel',
    message: 'Copy code to clipboard',
    description: 'The ARIA label for copy code blocks button',
  });
}

function waitForSpinnerPaint() {
  return new Promise((resolve) => {
    window.requestAnimationFrame(() => {
      window.setTimeout(resolve, 0);
    });
  });
}

function writeCodeToClipboard(code) {
  if (navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(code);
  }

  const textArea = document.createElement('textarea');
  textArea.value = code;
  textArea.setAttribute('readonly', '');
  textArea.style.position = 'fixed';
  textArea.style.top = '0';
  textArea.style.left = '-9999px';
  document.body.appendChild(textArea);
  textArea.select();

  try {
    document.execCommand('copy');
    return Promise.resolve();
  } finally {
    document.body.removeChild(textArea);
  }
}

function useCopyButton() {
  const {
    metadata: {code},
  } = useCodeBlockContext();
  const [copyState, setCopyState] = useState('idle');
  const copyTimeout = useRef(undefined);
  const copyInFlight = useRef(false);

  const copyCode = useCallback(async () => {
    if (copyInFlight.current) {
      return;
    }

    copyInFlight.current = true;
    window.clearTimeout(copyTimeout.current);
    setCopyState('copying');

    try {
      await waitForSpinnerPaint();
      await writeCodeToClipboard(code);
      copyInFlight.current = false;
      setCopyState('copied');
      copyTimeout.current = window.setTimeout(() => {
        setCopyState('idle');
      }, copiedDelay);
    } catch {
      copyInFlight.current = false;
      setCopyState('idle');
    }
  }, [code]);

  useEffect(
    () => () => {
      copyInFlight.current = false;
      window.clearTimeout(copyTimeout.current);
    },
    [],
  );

  return {copyCode, copyState};
}

function CopySpinner() {
  return (
    <span className={styles.copyButtonSpinner} aria-hidden="true">
      {Array.from({length: 12}, (_, index) => (
        <span className={styles.spinnerBlade} key={index} />
      ))}
    </span>
  );
}

export default function CopyButton({className}) {
  const {copyCode, copyState} = useCopyButton();
  const isCopying = copyState === 'copying';
  const isCopied = copyState === 'copied';

  return (
    <Button
      aria-disabled={isCopying}
      aria-label={ariaLabel(copyState)}
      title={title()}
      className={clsx(
        className,
        styles.copyButton,
        isCopying && styles.copyButtonCopying,
        isCopied && styles.copyButtonCopied,
      )}
      data-copy-state={copyState}
      onClick={copyCode}>
      <span className={styles.copyButtonIcons} aria-hidden="true">
        <IconCopy className={styles.copyButtonIcon} />
        <CopySpinner />
        <IconSuccess className={styles.copyButtonSuccessIcon} />
      </span>
    </Button>
  );
}
