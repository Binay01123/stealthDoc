import React, { useState, useRef, useEffect } from 'react';
import Head from '@docusaurus/Head';
import Layout from '@theme/Layout';
import styles from './playground.module.css';

export default function Playground() {
  // State
  const [signalIndex, setSignalIndex] = useState(0);
  const [dailyPL, setDailyPL] = useState(300);
  const [openPL, setOpenPL] = useState(200);
  const [logs, setLogs] = useState([]);

  const signalStates = ['NONE', 'BUY', 'SELL'];

  // Refs for focus
  const signalRef = useRef(null);
  const dailyRef = useRef(null);
  const openRef = useRef(null);
  const logAreaRef = useRef(null);

  // Logging
  const logAction = (msg) => {
    setLogs(prev => [...prev, msg]);
  };

  // Auto-scroll logs
  useEffect(() => {
    if (logAreaRef.current) {
      logAreaRef.current.scrollTop = logAreaRef.current.scrollHeight;
    }
  }, [logs]);

  // Format PL
  const formatPL = (val) => {
     const absVal = Math.abs(val).toLocaleString('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
     return val < 0 ? `-${absVal}` : absVal;
  };

  // Styling helper for PL boxes
  const getPLStyle = (val) => {
    return val < 0 
      ? { backgroundColor: '#ff3b3b', color: '#fff' }
      : { backgroundColor: '#a7d5fa', color: '#000' };
  };

  // Handlers
  const handleSignalKeyDown = (e) => {
    if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSignalIndex(prev => (prev + 1) % signalStates.length);
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSignalIndex(prev => (prev - 1 + signalStates.length) % signalStates.length);
    } else if (e.key === 'Tab') {
        e.preventDefault();
        const target = e.shiftKey ? openRef : dailyRef;
        target.current?.focus();
    }
  };

  const handleDailyKeyDown = (e) => {
    if (e.key === 'ArrowUp') {
        e.preventDefault();
        setDailyPL(prev => prev + 10);
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setDailyPL(prev => prev - 10);
    } else if (e.key === 'Tab') {
        e.preventDefault();
        const target = e.shiftKey ? signalRef : openRef;
        target.current?.focus();
    }
  };

  const handleOpenKeyDown = (e) => {
    if (e.key === 'ArrowUp') {
        e.preventDefault();
        setOpenPL(prev => prev + 10);
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setOpenPL(prev => prev - 10);
    } else if (e.key === 'Tab') {
        e.preventDefault();
        const target = e.shiftKey ? dailyRef : signalRef;
        target.current?.focus();
    }
  };

  const handleBuy = () => {
    logAction('clicked BUY');
    setOpenPL(0);
    setTimeout(() => openRef.current?.focus(), 1000);
  };

  const handleSell = () => {
    logAction('clicked SELL');
    setOpenPL(0);
    setTimeout(() => openRef.current?.focus(), 1000);
  };

  return (
    <Layout title="Playground" description="Nightshark Playground">
      <Head>
        <meta name="robots" content="noindex, follow" />
        <meta name="googlebot" content="noindex, follow" />
      </Head>
      <div className={styles.playgroundPage}>
        <div className={styles.container}>
          <div className={styles.title}>Nightshark PlayGround</div>
          <div className={styles.layoutRow}>
            
            <div className={styles.mainBox}>
                <div 
                    ref={signalRef}
                    tabIndex={0} 
                    className={styles.signalBox}
                    onKeyDown={handleSignalKeyDown}
                >
                    SIGNAL: {signalStates[signalIndex]}
                </div>

                <div className={styles.topRightBtns}>
                    <button className={styles.buyBtn} onClick={handleBuy}>BUY</button>
                    <button className={styles.sellBtn} onClick={handleSell}>SELL</button>
                </div>

                <div className={styles.plRow}>
                    <div className={styles.plCol}>
                        <div className={styles.plLabel}>Daily P/L</div>
                        <div 
                            ref={dailyRef}
                            tabIndex={0}
                            className={styles.plBox}
                            style={getPLStyle(dailyPL)}
                            onKeyDown={handleDailyKeyDown}
                        >
                            {formatPL(dailyPL)}
                        </div>
                    </div>

                    <div className={styles.plCol}>
                        <div className={styles.plLabel}>Open P/L</div>
                        <div 
                            ref={openRef}
                            tabIndex={0}
                            className={styles.plBox}
                            style={getPLStyle(openPL)}
                            onKeyDown={handleOpenKeyDown}
                        >
                            {formatPL(openPL)}
                        </div>
                    </div>
                </div>
            </div>

            <div className={styles.logArea} ref={logAreaRef}>
                {logs.map((log, i) => <div key={i}>{log}</div>)}
            </div>

          </div>
        </div>
      </div>
    </Layout>
  );
}
