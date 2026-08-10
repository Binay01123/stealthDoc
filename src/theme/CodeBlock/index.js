import React, { useRef, useState } from 'react';
import CodeBlock from '@theme-original/CodeBlock';
import clsx from 'clsx';

export default function CodeBlockWrapper(props) {
  const { metastring, title, children } = props;
  
  // Check if the code block should be collapsible (manual)
  const isCollapsible = metastring && /\b(collapse|collapsible)\b/.test(metastring);
  const defaultOpen = metastring && /\bopen\b/.test(metastring);

  if (isCollapsible) {
    const { title: _title, ...rest } = props;
    return (
      <details 
        className="code-block-collapsible" 
        open={defaultOpen}
      >
        <summary className="code-block-summary">
          {title || 'Show Code'}
        </summary>
        <CodeBlock {...rest} />
      </details>
    );
  }

  // Auto-collapse logic for long code blocks
  const [isExpanded, setIsExpanded] = useState(false);
  const wrapperRef = useRef(null);
  const lineCount = typeof children === 'string' ? children.split('\n').length : 0;
  const isLong = lineCount > 25; // Threshold for "too long"

  const collapseSnippet = () => {
    setIsExpanded(false);
    window.requestAnimationFrame(() => {
      wrapperRef.current?.scrollIntoView({
        behavior: 'smooth',
        block: 'start',
      });
      wrapperRef.current
        ?.querySelector('.expand-button')
        ?.focus({preventScroll: true});
    });
  };

  if (isLong) {
    return (
      <div
        ref={wrapperRef}
        className={clsx('code-block-wrapper', {'expanded': isExpanded})}>
        {isExpanded && (
          <div className="code-block-collapse-control">
            <button
              aria-expanded="true"
              className="collapse-button"
              onClick={collapseSnippet}
              type="button">
              Collapse Snippet
            </button>
          </div>
        )}
        <div className={clsx('code-block-content', { 'collapsed': !isExpanded })}>
          <CodeBlock {...props} />
        </div>
        {!isExpanded && (
          <div className="code-block-overlay">
            <button 
              aria-expanded="false"
              className="clean-btn expand-button" 
              onClick={() => setIsExpanded(true)}
              type="button"
            >
              Expand Snippet
            </button>
          </div>
        )}
      </div>
    );
  }

  return (
    <>
      <CodeBlock {...props} />
    </>
  );
}
