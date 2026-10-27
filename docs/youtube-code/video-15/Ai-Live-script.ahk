;======================================================
; KALSHI AI LIVE STRATEGY
;=======================================================
assets := ["BTC"]              ; BTC, ETH, SOL, XRP, DOGE, HYPE, BNB
orderSize := 1                 ; Live contracts per trade
timeDelay := 15                ; Request AI when this many minutes remain; 15 = session start
Obey_model := "YES"            ; YES trades the model direction; NO trades the opposite
Max_daily_profit := 400        ; Stop after settled agent PnL reaches this; 0 disables
Max_daily_Loss := -200         ; Stop after settled agent PnL reaches this; 0 disables

; ==================== Startup and validation ====================
model := ns_ai_model_name()
modelDisplayName := ns_ai_model_display_name()
modelProvider := ns_ai_provider()
aiBackendReady := ns_ai_backend_health_check()
settingsValid := true

pollIntervalMs := 700
marketRefreshMs := 5000       
priceRefreshMs := 1500         
balanceRefreshMs := 60000       

if (Trim(model) = "") {
    Log("ERROR: Select a model in AI Mode, then restart this script.")
    settingsValid := false
}
if (modelProvider = "") {
    Log("ERROR: The selected model does not include provider metadata. Reload AI Mode and select the model again.")
    settingsValid := false
}
if (!aiBackendReady) {
    Log("ERROR: The NightShark AI backend is unavailable.")
    settingsValid := false
}
if (!IsObject(assets) || assets.Length() = 0) {
    Log("ERROR: assets must contain at least one supported asset, for example [""BTC""] or [""BTC"", ""ETH""].")
    settingsValid := false
} else {
    for assetIndex, configuredAsset in assets {
        configuredAsset := Trim(configuredAsset)
        StringUpper, configuredAsset, configuredAsset
        if !RegExMatch(configuredAsset, "^(BTC|ETH|SOL|XRP|DOGE|HYPE|BNB)$") {
            Log("ERROR: assets contains unsupported value '" configuredAsset "'. Supported assets: BTC, ETH, SOL, XRP, DOGE, HYPE, BNB.")
            settingsValid := false
        } else {
            assets[assetIndex] := configuredAsset
        }
    }
}
orderSizeValid := IsNumericStr(orderSize) && (orderSize + 0) > 0
if (!orderSizeValid) {
    Log("ERROR: orderSize is '" orderSize "'. It needs to be a positive number of contracts, for example 1 or 2.5.")
    settingsValid := false
}
timeDelayValid := IsNumericStr(timeDelay) && (timeDelay + 0) > 0 && (timeDelay + 0) <= 15
if (!timeDelayValid) {
    Log("ERROR: timeDelay is '" timeDelay "'. Use a number greater than 0 and no more than 15 minutes.")
    settingsValid := false
}
obeyModelValue := Trim(Obey_model)
StringUpper, obeyModelValue, obeyModelValue
if (obeyModelValue != "YES" && obeyModelValue != "NO") {
    Log("ERROR: Obey_model is '" Obey_model "'. Use either ""YES"" or ""NO"".")
    settingsValid := false
} else {
    Obey_model := obeyModelValue
}
maxDailyProfitValid := IsNumericStr(Max_daily_profit) && (Max_daily_profit + 0) >= 0
if (!maxDailyProfitValid) {
    Log("ERROR: Max_daily_profit is '" Max_daily_profit "'. Use a positive dollar amount, or 0 to disable it.")
    settingsValid := false
}
maxDailyLossValid := IsNumericStr(Max_daily_Loss) && (Max_daily_Loss + 0) <= 0
if (!maxDailyLossValid) {
    Log("ERROR: Max_daily_Loss is '" Max_daily_Loss "'. Use a negative dollar amount, or 0 to disable it.")
    settingsValid := false
}
if (!settingsValid) {
    Log("ERROR: Fix the settings listed above and restart the script. Stopping now.")
    stopCode()
    return
}

; ==================== Market configuration and state ====================
enableLiveOrders := true
restDelay := 2000             
entryDiff := 0.02              
exitDiff := 0.02              
kalshiApiBase := "https://api.elections.kalshi.com"
assetSeriesMap := { "BTC": "KXBTC15M", "ETH": "KXETH15M", "SOL": "KXSOL15M", "XRP": "KXXRP15M", "DOGE": "KXDOGE15M", "HYPE": "KXHYPE15M", "BNB": "KXBNB15M" }
kalshiApiKeyId := ""
kalshiApiKeyFile := "reactions/apikey.json"
kalshiPrivateKeyFile := "reactions/privatekey.json"
kalshiPrivateKeyPath := ""
kalshiApiKeyResolvedPath := ""
kalshiPrivateKeyResolvedPath := ""
kalshiKeyPassphrase := ""
kalshiSignerPath := ""

; Track one open position per asset.
positions := {}
assetPhase := {}              
assetSessionQuarter := {}    
assetLastPriceLogTick := {}  
assetSnapshotCache := {}
assetMarketRefreshTick := {}
assetPriceCache := {}
assetPriceRefreshTick := {}
kalshiLastOrderResult := {}
kalshiShardFundingSessionStatus := {}
kalshiShardPendingTransfers := {} ; retained across market changes until reconciled
kalshiAggregateBalanceSnapshot := ""
kalshiBalanceNextRequestTick := 0
kalshiBalanceRetryCount := 0
pendingModelOutcomeAudits := {}
modelOutcomeAuditLastCheckTick := {}

kalshiRealizedPnl := 0
kalshiWins := 0
kalshiTradeCount := 0
kalshiHasUntrackedPosition := false
kalshiUntrackedPositionAssets := {}
kalshiAverageEntryFillNotional := 0
kalshiAverageEntryFillSize := 0
kalshiAverageEntryFillOrderIds := {}
pendingKalshiSettlements := {}
pendingKalshiClosedTrades := {}
kalshiSettlementLastCheckTick := {}
dailyPnlLimitTriggered := false

LoadKalshiCredentialsFromFiles()
if (kalshiSignerPath = "")
    kalshiSignerPath := FindNightSharkSigner()
Log("Application Started | LIVE MODE | " FormatAssetList(assets) " 15-minute AI direction strategy | provider: " modelProvider " | model: " modelDisplayName " | Obey model: " Obey_model " | AI request at " timeDelay "m remaining | order size: " KalshiFormatSize(orderSize) " | Agent PnL limits: " FmtPnl(Max_daily_profit) "/" FmtPnl(Max_daily_Loss))
if (!StartupCredentialCheck())
    return
UpdateKalshiPnlLogStreams()

; ==================== Strategy loop ====================
; Request one AI decision per market; SKIP stays flat, UP/DOWN enter and hold to resolution.
loop {
    if (dailyPnlLimitTriggered) {
        Sleep 250
        continue
    }
    ProcessPendingKalshiAccounting()
    if (CheckMaxDailyPnlAtSessionEnd()) {
        Sleep 250
        continue
    }

    for _, asset in assets {
        snapshot := GetKalshiMarketSnapshot(asset)
        if !IsObject(snapshot) {
            if (PositionSessionEnded(asset))
                MarkHeldToResolution(asset)
            else if IsObject(positions[asset])
                positions[asset].lastMark := ""
            noDataKey := asset "|NO_DATA_" CurrentQuarterIndex()
            ns_log_once(asset, noDataKey, asset " Waiting for market data")
            continue
        }

        up := snapshot.up
        down := snapshot.down
        ; Recompute from closeTime so cached market metadata still uses live time.
        minsLeft := SnapshotMinutesLeft(snapshot)
        if (minsLeft = "")
            minsLeft := MinutesRemainingInQuarter()
        sessionKey := (snapshot.marketTicker != "") ? snapshot.marketTicker : ((snapshot.closeTime != "") ? snapshot.closeTime : CurrentQuarterIndex())

        if (PositionSessionEnded(asset, snapshot)) {
            MarkHeldToResolution(asset)
            continue
        }

        if (!assetSessionQuarter.HasKey(asset) || assetSessionQuarter[asset] != sessionKey) {
            if (KalshiDailyPnlLimitsEnabled() && KalshiSessionAccountingPending()) {
                ns_log_once(asset, "PNL_SETTLEMENT_WAIT", asset " Waiting for prior-session PnL settlement before starting the next session")
                continue
            }
            assetSessionQuarter[asset] := sessionKey
            assetPhase[asset] := "WAIT_FUNDING"
            assetLastPriceLogTick[asset] := 0
            ns_log_once_reset(asset)
            Log(asset " New LIVE session (" snapshot.marketTicker ", shard " snapshot.exchangeIndex ")")
            LogStream("AI SIGNAL", "n/a")
            UpdateAgentPositionLogStream(asset)
            SetKalshiUntrackedPosition(asset, false)

            continue
        }

        if IsObject(positions[asset]) {
            TryReconcileKalshiEntry(asset)
            pos := positions[asset]
            currentBid := KalshiSnapshotPositionBid(snapshot, pos.side, pos.size)
            positions[asset].lastMark := (currentBid != "") ? currentBid + 0 : ""
            assetPhase[asset] := "IN_POSITION"
            UpdateKalshiLogStream(asset, snapshot)
            continue
        }

        if (assetPhase[asset] = "BUY_FAILED") {
            ns_log_once(asset, "BUY_FAILED", asset " Buy failed earlier, waiting for next session")
            continue
        }

        if (assetPhase[asset] = "HAS_POSITION") {
            ns_log_once(asset, "HAS_POSITION", asset " Existing position, waiting for next session")
            continue
        }

        if (assetPhase[asset] = "FUNDING_FAILED") {
            ns_log_once(asset, "FUNDING_FAILED", asset " Funding request rejected; live entry is paused")
            continue
        }

        if (assetPhase[asset] = "AI_FAILED") {
            ns_log_once(asset, "AI_FAILED", asset " " modelProvider " analysis failed, waiting for next session")
            continue
        }

        if (assetPhase[asset] = "SETTLEMENT_PENDING" || assetPhase[asset] = "SESSION_ENDED") {
            ns_log_once(asset, "SESSION_ENDED", asset " Session ended, waiting for the next market")
            continue
        }

        if (assetPhase[asset] = "WAIT_FUNDING") {
            if (minsLeft = "") {
                ns_log_once(asset, "FUNDING_TIME_MISSING", asset " Waiting for the session clock before funding")
                continue
            }
            if (minsLeft <= 0) {
                assetPhase[asset] := "SESSION_ENDED"
                ns_log_once(asset, "FUNDING_WINDOW_ENDED", asset " Market closed while waiting for funding")
                continue
            }
            fundingFailed := false
            if (!EnsureKalshiShardFunding(asset, snapshot.exchangeIndex, fundingFailed)) {
                if (fundingFailed)
                    assetPhase[asset] := "FUNDING_FAILED"
                continue
            }

            ; An unavailable position read must not be treated as a flat account.
            existingPositionSize := GetKalshiPositionSize(snapshot.marketTicker, 1, snapshot.exchangeIndex)
            if (existingPositionSize = "") {
                ns_log_once(asset, "FUNDING_POSITION_WAIT", asset " Funding ready; waiting for existing-position check")
                continue
            }
            if (existingPositionSize > 0) {
                assetPhase[asset] := "HAS_POSITION"
                SetKalshiUntrackedPosition(asset, true)
                Log(asset " Existing position found; no new AI order will be placed this session")
            } else {
                assetPhase[asset] := "WAIT_AI_WINDOW"
                Log(asset " Shard funding ready")
            }
            ; Refresh the market and session clock before requesting AI analytics.
            continue
        }

        if (assetPhase[asset] = "WAIT_AI_WINDOW") {
            if (minsLeft = "") {
                ns_log_once(asset, "AI_WINDOW_TIME_MISSING", asset " Waiting for the session clock before requesting AI analytics")
                continue
            }
            if (minsLeft <= 0) {
                assetPhase[asset] := "SESSION_ENDED"
                ns_log_once(asset, "SESSION_ENDED", asset " Session ended before the AI analytics request")
                continue
            }
            if (minsLeft > (timeDelay + 0)) {
                ns_log_once(asset, "WAIT_AI_WINDOW", asset " Waiting to request AI analytics at " timeDelay " minutes remaining")
                continue
            }

            Log(asset " Requesting AI analytics with " FmtMinutes(minsLeft) " minutes remaining")
            aiDecision := ns_ai_request_once(asset, sessionKey, snapshot.closeTime)
            if !IsObject(aiDecision) {
                if (ns_ai_fatal_stop_requested())
                    return
                assetPhase[asset] := "AI_FAILED"
                Log(asset " " modelProvider " analysis unavailable; skipping this session")
                continue
            }
            RegisterModelOutcomeAudit(aiDecision.provider, asset, sessionKey, snapshot, aiDecision)
            assetPhase[asset] := "READY_TO_ENTER"
            LogStream("AI SIGNAL", aiDecision.direction)
            UpdateAgentPositionLogStream(asset, aiDecision)
        }

        aiDecision := ns_ai_cached_decision(asset, sessionKey)
        if !IsObject(aiDecision) {
            assetPhase[asset] := "AI_FAILED"
            ns_log_once(asset, "AI_DECISION_MISSING", asset " " modelProvider " decision missing; skipping this session")
            continue
        }
        if (aiDecision.direction = "SKIP") {
            assetPhase[asset] := "AI_SKIPPED"
            UpdateKalshiLogStream(asset, snapshot)
            ns_log_once(asset, "AI_SKIPPED", asset " AI chose SKIP | no live order | " aiDecision.reason)
            continue
        }
        ; Only explicit entry decisions may reach the order block.
        if (aiDecision.direction != "UP" && aiDecision.direction != "DOWN") {
            assetPhase[asset] := "AI_FAILED"
            ns_log_once(asset, "AI_INVALID", asset " Invalid AI decision; no live order")
            continue
        }

        freshSnap := GetKalshiMarketSnapshot(asset)
        if !IsObject(freshSnap) {
            ns_log_once(asset, "FRESH_QUOTE_MISSING", asset " Fresh Kalshi quote unavailable; entry will retry")
            continue
        }
        if (freshSnap.marketTicker != sessionKey) {
            assetPhase[asset] := "SESSION_ENDED"
            Log(asset " Market changed before entry; no live order placed for " sessionKey)
            continue
        }
        snapshot := freshSnap
        up := snapshot.up
        down := snapshot.down

        UpdateKalshiLogStream(asset, snapshot)
        modelDirection := aiDecision.direction
        side := ResolveModelTradeDirection(modelDirection)
        if (side = "") {
            assetPhase[asset] := "AI_FAILED"
            Log(asset " Could not resolve trade direction from model signal " modelDirection " with Obey_model=" Obey_model)
            continue
        }
        entryPrice := (side = "UP") ? up : down
        if (entryPrice = "" || entryPrice <= 0 || entryPrice >= 1) {
            ns_log_once(asset, "ENTRY_QUOTE_MISSING", asset " Current " side " ask unavailable; entry will retry when a quote appears")
            continue
        }

        if !CanPlaceOrderNow(asset) {
            ns_log_once(asset, "NO_CREDS", asset " Missing credentials; live entry is paused")
            continue
        }

        existingPositionSize := GetKalshiPositionSize(snapshot.marketTicker, 3, snapshot.exchangeIndex)
        if (existingPositionSize = "") {
            ns_log_once(asset, "POSITION_CHECK_FAILED", asset " Position check unavailable; live entry is paused")
            continue
        }
        if (existingPositionSize > 0) {
            assetPhase[asset] := "HAS_POSITION"
            SetKalshiUntrackedPosition(asset, true)
            Log(asset " Existing position found; no new order will be placed this session")
            continue
        }

        Log(asset " " ns_ai_provider(aiDecision) " " ns_ai_model_display_name(aiDecision) " chose " modelDirection " | Obey_model=" Obey_model " | trade side=" side " | current ask " Fmt(entryPrice) " — placing LIVE order")
        buyConfirmed := false
        loop, 4 {
            if (A_Index > 1 && HasExistingPosition(snapshot.marketTicker, snapshot.exchangeIndex)) {
                Log(asset " Position detected before retry " A_Index "; skipping duplicate order")
                buyConfirmed := true
                break
            }
            if (A_Index > 1) {
                freshSnap := GetKalshiMarketSnapshot(asset)
                if (!IsObject(freshSnap) || freshSnap.marketTicker != sessionKey) {
                    Log(asset " Entry retry canceled: market changed or quote is unavailable")
                    break
                }
                snapshot := freshSnap
                entryPrice := (side = "UP") ? snapshot.up : snapshot.down
            }
            if (entryPrice = "" || entryPrice <= 0 || entryPrice >= 1) {
                Log(asset " Entry retry canceled: current " side " ask is unavailable")
                break
            }
            if BuyPosition(asset, snapshot.marketTicker, side, entryPrice, snapshot.exchangeIndex) {
                buyConfirmed := true
                break
            }
            if (KalshiResultValue(kalshiLastOrderResult, "fatal", false))
                break
            if (A_Index < 4) {
                Log(asset " Entry retry " A_Index "/3 | " KalshiLastOrderApiSummary())
                Sleep 1000
            }
        }

        if (buyConfirmed) {
            SetKalshiUntrackedPosition(asset, false)
            orderId := KalshiResultValue(kalshiLastOrderResult, "orderId", "")
            fillSummary := KalshiLastOrderFillSummary()
            accountingReady := KalshiFillSummaryReady(fillSummary)
            fillPrice := accountingReady ? fillSummary.price + 0 : entryPrice + 0
            fillPriceSource := accountingReady ? fillSummary.source : "detected price fallback"
            if (!accountingReady)
                Log("WARN: " asset " Exact entry fills/fees are pending; live PnL will wait for reconciliation")
            confirmedPositionSize := KalshiResultValue(kalshiLastOrderResult, "positionSize", "")
            posSize := accountingReady ? fillSummary.size + 0 : confirmedPositionSize
            if (posSize = "" || posSize <= 0)
                posSize := GetKalshiPositionSize(snapshot.marketTicker, 3, snapshot.exchangeIndex)
            if (posSize = "" || posSize <= 0)
                posSize := orderSize + 0
            entryFees := accountingReady ? fillSummary.fees + 0 : 0
            initialMark := KalshiSnapshotPositionBid(snapshot, side, posSize)
            positions[asset] := { side: side, entry: fillPrice, entryFees: entryFees, size: posSize, expectedSize: posSize, accountingReady: accountingReady, entryOrderId: orderId, ticker: snapshot.marketTicker, exchangeIndex: snapshot.exchangeIndex, quarterIndex: CurrentQuarterIndex(), lastMark: initialMark }
            RecordKalshiEntryFillForAverage(positions[asset])
            MarkModelOutcomeAuditOrderPlaced(asset, sessionKey, orderId, side)
            positions[asset].aiDirection := modelDirection
            positions[asset].tradeDirection := side
            positions[asset].obeyModel := Obey_model
            positions[asset].aiModel := aiDecision.model
            assetPhase[asset] := "IN_POSITION"
            assetLastPriceLogTick[asset] := 0
            UpdateKalshiLogStream(asset, snapshot)
            if (accountingReady)
                Log(asset " LIVE position confirmed | fill " Fmt(fillPrice) " | size " KalshiFormatSize(posSize) " | entry fees " FmtMoney(entryFees) " (" fillPriceSource ")")
            else
                Log(asset " LIVE position confirmed | exact fill accounting pending")
            Log(asset " Holding LIVE " side " to market resolution")
        } else if (!KalshiResultValue(kalshiLastOrderResult, "fatal", false)) {
            assetPhase[asset] := "BUY_FAILED"
            Log(asset " Entry order not filled after 4 attempts; skipping session | " KalshiLastOrderApiSummary())
        }
    }

    ProcessPendingKalshiAccounting()
    UpdateKalshiPnlLogStreams()
    CheckMaxDailyPnlAtSessionEnd()
    Random, pollJitterMs, 0, 250
    sleepMs := pollIntervalMs + pollJitterMs
    Sleep %sleepMs%
}

return

; ==================== Position, settlement and PnL helpers ====================
PositionSessionEnded(asset, snapshot := "") {
    global positions
    if !IsObject(positions[asset])
        return false

    pos := positions[asset]
    if (IsObject(snapshot) && snapshot.marketTicker != "" && pos.HasKey("ticker") && pos.ticker != "" && snapshot.marketTicker != pos.ticker)
        return true
    if (pos.HasKey("quarterIndex") && CurrentQuarterIndex() != pos.quarterIndex)
        return true
    return false
}

MarkHeldToResolution(asset) {
    global positions, assetPhase, pendingKalshiSettlements
    if !IsObject(positions[asset])
        return

    pos := positions[asset]
    pos.asset := asset
    pos.lastMark := ""
    settlementKey := (pos.HasKey("ticker") && pos.ticker != "") ? pos.ticker : asset "|" A_TickCount
    pendingKalshiSettlements[settlementKey] := pos
    Log(asset " LIVE " pos.side " held to resolution | PnL settlement pending")
    positions.Delete(asset)
    UpdateAgentPositionLogStream(asset)
    ClearKalshiMarketCache(asset)
    assetPhase[asset] := "SETTLEMENT_PENDING"
}

UpdateKalshiLogStream(asset, snapshot) {
    if !IsObject(snapshot)
        return ""

    priceObj := GetCachedKalshiPriceObj(asset)
    livePrice := (IsObject(priceObj) && priceObj.HasKey("price") && priceObj.price > 0) ? priceObj.price : ""
    LiveDelta := ""
    if (livePrice != "" && IsObject(priceObj) && priceObj.HasKey("open15m") && priceObj.open15m > 0)
        LiveDelta := Abs(priceObj.open15m - livePrice)
    LogMonitoringStream(asset, snapshot, livePrice, LiveDelta)
    return LiveDelta
}

LogMonitoringStream(asset, snapshot, livePrice := "", LiveDelta := "") {
    if !IsObject(snapshot)
        return
    if (livePrice != "")
        LogStream(asset, FmtOrNA(livePrice))
    else
        LogStream(asset, "n/a")
    LogStream("up", FmtOrNA(snapshot.up))
    LogStream("down", FmtOrNA(snapshot.down))
    LogStream("LIVE DELTA", FmtLiveDeltaOrNA(LiveDelta))
    LogStream("AVERAGE FILL", FmtAverageFillOrNA(GetKalshiAverageFillForLogStream()))
    sessionKey := snapshot.HasKey("marketTicker") ? snapshot.marketTicker : ""
    aiDecision := ns_ai_cached_decision(asset, sessionKey)
    if IsObject(aiDecision)
        LogStream("AI SIGNAL", aiDecision.direction)
    else
        LogStream("AI SIGNAL", "n/a")
    UpdateAgentPositionLogStream(asset, aiDecision)
}

GetKalshiAverageFillForLogStream() {
    global kalshiAverageEntryFillNotional, kalshiAverageEntryFillSize
    if (kalshiAverageEntryFillSize <= 0)
        return ""
    return kalshiAverageEntryFillNotional / kalshiAverageEntryFillSize
}

UpdateAgentPositionLogStream(asset, aiDecision := "") {
    global positions
    positionValue := ""
    if IsObject(positions[asset]) && positions[asset].HasKey("side") {
        side := positions[asset].side
        if (side = "UP" || side = "DOWN")
            positionValue := side
    }
    if (positionValue = "" && IsObject(aiDecision) && aiDecision.direction = "SKIP")
        positionValue := "SKIP"

    if (positionValue = "")
        LogStreamRemove("POSITION")
    else
        LogStream("POSITION", positionValue)
}

GetCachedKalshiPriceObj(asset) {
    global assetPriceCache, assetPriceRefreshTick, priceRefreshMs
    nowTick := A_TickCount

    if (assetPriceCache.HasKey(asset) && assetPriceRefreshTick.HasKey(asset)) {
        if ((nowTick - assetPriceRefreshTick[asset]) < priceRefreshMs)
            return assetPriceCache[asset]
    }

    priceObj := GetKalshiPrice(asset)
    assetPriceRefreshTick[asset] := nowTick
    if (IsObject(priceObj) && priceObj.HasKey("price") && priceObj.price > 0) {
        assetPriceCache[asset] := priceObj
        return priceObj
    }

    if (assetPriceCache.HasKey(asset))
        return assetPriceCache[asset]
    return ""
}

ResolveModelTradeDirection(modelDirection) {
    global Obey_model
    if (modelDirection = "SKIP")
        return "SKIP"
    if (modelDirection != "UP" && modelDirection != "DOWN")
        return ""
    if (Obey_model = "YES")
        return modelDirection
    return (modelDirection = "UP") ? "DOWN" : "UP"
}

FmtOrNA(price) {
    if (price = "")
        return "n/a"
    return Fmt(price)
}

FmtAverageFillOrNA(price) {
    if (price = "")
        return "n/a"
    return Format("{:.4f}", price + 0)
}

FmtLiveDeltaOrNA(value) {
    if (value = "")
        return "n/a"

    value := value + 0
    if (Abs(value) >= 1)
        return Round(value, 2)
    return Round(value, 4)
}

FmtMinutes(value) {
    if (value = "")
        return "n/a"
    return Round(value + 0, 2)
}

Fmt(price) {
    return Round(price + 0, 2)
}

FmtMoney(value) {
    return Format("{:.4f}", value + 0)
}

FmtPnl(value) {
    if (value = "")
        return "n/a"
    value := Round(value + 0, 4)
    if (value > 0)
        return "+" Format("{:.4f}", value)
    return Format("{:.4f}", value)
}

KalshiFormatSize(size) {
    value := Round((size + 0) * 100) / 100.0
    text := Format("{:.2f}", value)
    while (InStr(text, ".") && SubStr(text, StrLen(text), 1) = "0")
        text := SubStr(text, 1, StrLen(text) - 1)
    if (SubStr(text, StrLen(text), 1) = ".")
        text := SubStr(text, 1, StrLen(text) - 1)
    return text
}

BuyPosition(asset, marketTicker, side, price, exchangeIndex := -1) {
    global orderSize
    return PlaceKalshiOrder("BUY", marketTicker, side, price, orderSize, "", exchangeIndex)
}

HasExistingPosition(marketTicker, exchangeIndex := "") {
    size := GetKalshiPositionSize(marketTicker, 1, exchangeIndex)
    return (size != "" && size > 0)
}

GetKalshiPositionSize(marketTicker, maxAttempts := 1, exchangeIndex := "") {
    if (marketTicker = "")
        return ""

    endpoint := "/trade-api/v2/portfolio/positions?ticker=" marketTicker
    if (exchangeIndex != "")
        endpoint .= "&exchange_index=" NormalizeKalshiExchangeIndex(exchangeIndex)

    attempt := 1
    while (attempt <= maxAttempts) {
        res := KalshiSignedRequest("GET", endpoint)
        if IsObject(res) && (res.status = 200) {
            qty := JsonField(res.body, "position_fp")
            if (qty = "")
                return 0
            return Abs(qty + 0)
        }
        if (attempt < maxAttempts)
            Sleep 150
        attempt++
    }
    return ""
}

NewKalshiFillSummary() {
    return { size: 0, notional: 0, price: "", fees: 0, feesKnown: true, source: "" }
}

GetKalshiOrderFillSummary(orderId, contractSide, maxAttempts := 1) {
    if (orderId = "")
        return NewKalshiFillSummary()

    attempt := 1
    while (attempt <= maxAttempts) {
        summary := NewKalshiFillSummary()
        cursor := ""
        page := 1
        pagesComplete := true
        while (page <= 100) {
            endpoint := "/trade-api/v2/portfolio/fills?limit=1000&order_id=" orderId
            if (cursor != "")
                endpoint .= "&cursor=" KalshiQueryEncode(cursor)
            res := KalshiSignedRequest("GET", endpoint)
            if !IsObject(res) || (res.status != 200) {
                pagesComplete := false
                break
            }

            pageSummary := ExtractKalshiFillSummary(res.body, contractSide, orderId)
            AccumulateKalshiFillSummary(summary, pageSummary)
            nextCursor := JsonField(res.body, "cursor")
            if (nextCursor = "")
                break
            if (nextCursor = cursor) {
                pagesComplete := false
                break
            }
            cursor := nextCursor
            page++
        }
        if (page > 100)
            pagesComplete := false
        if (pagesComplete && summary.size > 0)
            return summary
        if (attempt < maxAttempts)
            Sleep 150
        attempt++
    }
    return NewKalshiFillSummary()
}

ExtractKalshiFillSummary(json, contractSide, orderId := "") {
    summary := NewKalshiFillSummary()
    sawFeeField := false
    scanPos := 1
    while (matchPos := RegExMatch(json, "\{[^{}]*\}", fillJson, scanPos)) {
        scanPos := matchPos + StrLen(fillJson)
        if (JsonField(fillJson, "fill_id") = "")
            continue
        if (orderId != "" && JsonField(fillJson, "order_id") != orderId)
            continue
        count := GetFirstNonEmptyJsonField(fillJson, ["count_fp", "count"])
        if (!IsNumericStr(count) || (count + 0) <= 0)
            continue

        if (contractSide = "UP")
            fillPrice := GetKalshiDollarPrice(fillJson, "yes_price_dollars", "yes_price")
        else
            fillPrice := GetKalshiDollarPrice(fillJson, "no_price_dollars", "no_price")
        if (fillPrice = "") {
            legacyPriceField := (contractSide = "UP") ? "yes_price_fixed" : "no_price_fixed"
            fillPrice := GetFirstNonEmptyJsonField(fillJson, [legacyPriceField])
        }
        if (!IsNumericStr(fillPrice) || (fillPrice + 0) <= 0)
            continue

        fee := JsonField(fillJson, "fee_cost")
        if (IsNumericStr(fee)) {
            sawFeeField := true
            summary.fees += fee + 0
        }
        summary.notional += (fillPrice + 0) * (count + 0)
        summary.size += count + 0
    }

    if (summary.size > 0) {
        summary.price := summary.notional / summary.size
        summary.feesKnown := sawFeeField
        summary.source := "Kalshi fills API"
    }
    return summary
}

KalshiFillSummaryReady(summary) {
    return IsObject(summary) && summary.size > 0 && summary.price != "" && summary.feesKnown
}

AccumulateKalshiFillSummary(target, source) {
    if !IsObject(target) || !IsObject(source) || source.size <= 0
        return
    target.size += source.size + 0
    target.notional += source.notional + 0
    target.fees += source.fees + 0
    target.feesKnown := target.feesKnown && source.feesKnown
    target.price := target.notional / target.size
    if (target.source = "")
        target.source := source.source
}

KalshiLastOrderFillSummary() {
    global kalshiLastOrderResult
    if IsObject(kalshiLastOrderResult) && kalshiLastOrderResult.HasKey("fillSummary") && IsObject(kalshiLastOrderResult.fillSummary)
        return kalshiLastOrderResult.fillSummary
    return NewKalshiFillSummary()
}

KalshiPositionAccountingReady(pos) {
    return IsObject(pos) && pos.HasKey("accountingReady") && pos.accountingReady
        && pos.HasKey("entry") && pos.HasKey("entryFees") && pos.HasKey("size") && pos.size > 0
}

RecordKalshiEntryFillForAverage(pos) {
    global kalshiAverageEntryFillNotional, kalshiAverageEntryFillSize, kalshiAverageEntryFillOrderIds
    if !KalshiPositionAccountingReady(pos)
        return false

    orderId := pos.HasKey("entryOrderId") ? pos.entryOrderId : ""
    if (orderId = "" || kalshiAverageEntryFillOrderIds.HasKey(orderId))
        return false

    fillSize := pos.size + 0
    kalshiAverageEntryFillNotional += (pos.entry + 0) * fillSize
    kalshiAverageEntryFillSize += fillSize
    kalshiAverageEntryFillOrderIds[orderId] := true
    return true
}

ReconcileKalshiPositionObject(pos, force := false) {
    if (KalshiPositionAccountingReady(pos)) {
        RecordKalshiEntryFillForAverage(pos)
        return true
    }
    if !IsObject(pos) || !pos.HasKey("entryOrderId") || pos.entryOrderId = ""
        return false

    nowTick := A_TickCount
    if (!force && pos.HasKey("accountingLastCheckTick") && (nowTick - pos.accountingLastCheckTick) < 2000)
        return false
    pos.accountingLastCheckTick := nowTick

    summary := GetKalshiOrderFillSummary(pos.entryOrderId, pos.side, force ? 3 : 1)
    if (!KalshiFillSummaryReady(summary))
        return false
    expectedSize := pos.HasKey("expectedSize") ? pos.expectedSize + 0 : pos.size + 0
    if (summary.size < (expectedSize - 0.000001))
        return false

    pos.entry := summary.price + 0
    pos.entryFees := summary.fees + 0
    pos.size := summary.size + 0
    pos.accountingReady := true
    RecordKalshiEntryFillForAverage(pos)
    return true
}

TryReconcileKalshiEntry(asset) {
    global positions
    if !IsObject(positions[asset]) || KalshiPositionAccountingReady(positions[asset])
        return true
    if (ReconcileKalshiPositionObject(positions[asset])) {
        Log(asset " Exact entry accounting confirmed | fill " Fmt(positions[asset].entry) " | size " KalshiFormatSize(positions[asset].size) " | fees " FmtMoney(positions[asset].entryFees))
        return true
    }
    return false
}

RecordKalshiClosedTrade(asset, pos, exitSummary, reason) {
    global kalshiRealizedPnl, kalshiWins, kalshiTradeCount
    size := pos.size + 0
    exitPrice := exitSummary.price + 0
    entryFees := pos.entryFees + 0
    exitFees := exitSummary.fees + 0
    pnl := (exitPrice - (pos.entry + 0)) * size - entryFees - exitFees

    kalshiRealizedPnl += pnl
    kalshiTradeCount++
    if (pnl > 0)
        kalshiWins++

    Log(asset " LIVE " pos.side " closed | entry " Fmt(pos.entry) " | exit fill " Fmt(exitPrice) " | size " KalshiFormatSize(size) " | fees " FmtMoney(entryFees + exitFees) " | net PnL " FmtPnl(pnl) " | " reason)
}

ProcessPendingKalshiSettlements() {
    global pendingKalshiSettlements, kalshiApiBase, kalshiSettlementLastCheckTick
    resolvedKeys := []
    for settlementKey, pos in pendingKalshiSettlements {
        if !IsObject(pos) || !ReconcileKalshiPositionObject(pos)
            continue

        nowTick := A_TickCount
        if (kalshiSettlementLastCheckTick.HasKey(settlementKey) && (nowTick - kalshiSettlementLastCheckTick[settlementKey]) < 2000)
            continue
        kalshiSettlementLastCheckTick[settlementKey] := nowTick

        body := HttpGet(kalshiApiBase "/trade-api/v2/markets/" pos.ticker "?_=" nowTick)
        result := JsonField(body, "result")
        StringLower, result, result
        if (result != "yes" && result != "no")
            continue

        yesSettle := (result = "yes") ? 1 : 0
        settlePrice := (pos.side = "UP") ? yesSettle : 1 - yesSettle
        settleSummary := NewKalshiFillSummary()
        settleSummary.size := pos.size + 0
        settleSummary.price := settlePrice
        settleSummary.notional := settlePrice * settleSummary.size
        settleSummary.fees := 0
        settleSummary.feesKnown := true
        settleSummary.source := "Kalshi settlement result"
        RecordKalshiClosedTrade(pos.asset, pos, settleSummary, "held_to_resolution")
        resolvedKeys.Push(settlementKey)
        kalshiSettlementLastCheckTick.Delete(settlementKey)
    }
    for _, settlementKey in resolvedKeys
        pendingKalshiSettlements.Delete(settlementKey)
}

ProcessPendingKalshiAccounting() {
    ProcessPendingKalshiSettlements()
    ProcessPendingModelOutcomeAudits()
}

RegisterModelOutcomeAudit(provider, asset, sessionKey, snapshot, decision) {
    global pendingModelOutcomeAudits, Obey_model
    if (sessionKey = "" || !IsObject(decision))
        return false

    if (decision.direction = "SKIP") {
        Log("MODEL DECISION AUDIT | provider=" provider " | model=" decision.model " | asset=" asset " | market=" sessionKey " | decision=SKIP | trade_status=NO_ORDER_PLACED | reason=" decision.reason)
        return true
    }
    auditKey := asset "|" sessionKey
    if (pendingModelOutcomeAudits.HasKey(auditKey))
        return true

    ticker := IsObject(snapshot) && snapshot.HasKey("marketTicker") ? snapshot.marketTicker : ""
    if (ticker = "" && RegExMatch(sessionKey, "i)^KX"))
        ticker := sessionKey
    closeTime := IsObject(snapshot) && snapshot.HasKey("closeTime") ? snapshot.closeTime : ""
    pendingModelOutcomeAudits[auditKey] := { provider: provider
        , asset: asset
        , sessionKey: sessionKey
        , ticker: ticker
        , closeTime: closeTime
        , quarterIndex: CurrentQuarterIndex()
        , model: decision.model
        , predictedDirection: decision.direction
        , tradeDirection: ""
        , orderPlaced: false
        , orderId: "" }
    Log("MODEL PREDICTION AUDIT | provider=" provider " | model=" decision.model " | asset=" asset " | market=" ticker " | predicted_direction=" decision.direction " | obey_model=" Obey_model " | planned_trade_direction=" ResolveModelTradeDirection(decision.direction))
    return true
}

MarkModelOutcomeAuditOrderPlaced(asset, sessionKey, orderId := "", tradeDirection := "") {
    global pendingModelOutcomeAudits
    auditKey := asset "|" sessionKey
    if (!pendingModelOutcomeAudits.HasKey(auditKey))
        return false
    pendingModelOutcomeAudits[auditKey].orderPlaced := true
    pendingModelOutcomeAudits[auditKey].orderId := orderId
    pendingModelOutcomeAudits[auditKey].tradeDirection := tradeDirection
    return true
}

ProcessPendingModelOutcomeAudits() {
    global pendingModelOutcomeAudits, modelOutcomeAuditLastCheckTick, kalshiApiBase
    resolvedKeys := []
    for auditKey, audit in pendingModelOutcomeAudits {
        if !IsObject(audit)
            continue

        sessionEnded := false
        if (audit.closeTime != "") {
            minutesLeft := MinutesUntilIsoUtc(audit.closeTime)
            if (minutesLeft != "")
                sessionEnded := minutesLeft <= 0
        }
        if (!sessionEnded)
            sessionEnded := CurrentQuarterIndex() != audit.quarterIndex
        if (!sessionEnded)
            continue

        tradeDirection := audit.HasKey("tradeDirection") && audit.tradeDirection != "" ? audit.tradeDirection : "NONE"

        if (audit.ticker = "") {
            tradeStatus := audit.orderPlaced ? "ORDER_PLACED" : "NO_ORDER_PLACED"
            Log("MODEL OUTCOME AUDIT | provider=" audit.provider " | model=" audit.model " | asset=" audit.asset " | market=n/a | predicted_direction=" audit.predictedDirection " | trade_direction=" tradeDirection " | trade_status=" tradeStatus " | market_outcome=UNAVAILABLE | prediction_result=UNAVAILABLE | reason=missing_market_ticker")
            resolvedKeys.Push(auditKey)
            continue
        }

        nowTick := A_TickCount
        if (modelOutcomeAuditLastCheckTick.HasKey(auditKey) && (nowTick - modelOutcomeAuditLastCheckTick[auditKey]) < 5000)
            continue
        modelOutcomeAuditLastCheckTick[auditKey] := nowTick

        body := HttpGet(kalshiApiBase "/trade-api/v2/markets/" audit.ticker "?_audit=" nowTick)
        result := JsonField(body, "result")
        StringLower, result, result
        if (result != "yes" && result != "no")
            continue

        marketDirection := (result = "yes") ? "UP" : "DOWN"
        predictionResult := (audit.predictedDirection = marketDirection) ? "MATCH" : "MISS"
        tradeStatus := audit.orderPlaced ? "ORDER_PLACED" : "NO_ORDER_PLACED"
        auditLog := "MODEL OUTCOME AUDIT | provider=" audit.provider " | model=" audit.model " | asset=" audit.asset " | market=" audit.ticker " | predicted_direction=" audit.predictedDirection " | trade_direction=" tradeDirection " | trade_status=" tradeStatus " | market_outcome=" marketDirection " | kalshi_result=" result " | prediction_result=" predictionResult
        if (audit.orderId != "")
            auditLog .= " | order_id=" audit.orderId
        Log(auditLog)
        resolvedKeys.Push(auditKey)
        modelOutcomeAuditLastCheckTick.Delete(auditKey)
    }
    for _, auditKey in resolvedKeys
        pendingModelOutcomeAudits.Delete(auditKey)
}

KalshiSnapshotPositionBid(snapshot, side, size := "") {
    if !IsObject(snapshot)
        return ""
    bidField := (side = "UP") ? "upBid" : "downBid"
    bidSizeField := (side = "UP") ? "upBidSize" : "downBidSize"
    if (!snapshot.HasKey(bidField) || snapshot[bidField] = "")
        return ""
    if (size != "") {
        if (!snapshot.HasKey(bidSizeField) || snapshot[bidSizeField] = "" || snapshot[bidSizeField] < ((size + 0) - 0.000001))
            return ""
    }
    if (snapshot[bidField] != "")
        return snapshot[bidField] + 0
    return ""
}

ComputeKalshiLivePnl() {
    global kalshiRealizedPnl, positions, pendingKalshiSettlements, pendingKalshiClosedTrades, kalshiHasUntrackedPosition
    if (kalshiHasUntrackedPosition)
        return ""
    if (IsObject(pendingKalshiClosedTrades) && pendingKalshiClosedTrades.Count() > 0)
        return ""

    ; Live trades are marked at the executable bid and include charged entry fees.
    ; Settlement does not add an exit fee.
    pnl := kalshiRealizedPnl + 0
    for _, pos in positions {
        if !IsObject(pos) || !KalshiPositionAccountingReady(pos)
            return ""
        mark := pos.HasKey("lastMark") ? pos.lastMark : ""
        if (mark = "")
            return ""
        pnl += ((mark + 0) - (pos.entry + 0)) * (pos.size + 0) - (pos.entryFees + 0)
    }
    for _, pos in pendingKalshiSettlements {
        if !IsObject(pos) || !KalshiPositionAccountingReady(pos)
            return ""
        mark := pos.HasKey("lastMark") ? pos.lastMark : ""
        if (mark = "")
            return ""
        pnl += ((mark + 0) - (pos.entry + 0)) * (pos.size + 0) - (pos.entryFees + 0)
    }
    return pnl
}

KalshiSessionAccountingPending() {
    global pendingKalshiSettlements, pendingKalshiClosedTrades
    return (IsObject(pendingKalshiSettlements) && pendingKalshiSettlements.Count() > 0)
        || (IsObject(pendingKalshiClosedTrades) && pendingKalshiClosedTrades.Count() > 0)
}

SetKalshiUntrackedPosition(asset, hasPosition) {
    global kalshiUntrackedPositionAssets, kalshiHasUntrackedPosition
    if !IsObject(kalshiUntrackedPositionAssets)
        kalshiUntrackedPositionAssets := {}
    if (hasPosition)
        kalshiUntrackedPositionAssets[asset] := true
    else if (kalshiUntrackedPositionAssets.HasKey(asset))
        kalshiUntrackedPositionAssets.Delete(asset)
    kalshiHasUntrackedPosition := kalshiUntrackedPositionAssets.Count() > 0
}

KalshiHasOpenOrUnsettledExposure() {
    global positions, pendingKalshiSettlements, pendingKalshiClosedTrades, kalshiHasUntrackedPosition
    if (kalshiHasUntrackedPosition)
        return true
    for _, pos in positions {
        if IsObject(pos)
            return true
    }
    if (KalshiSessionAccountingPending())
        return true
    return false
}

KalshiDailyPnlLimitsEnabled() {
    global Max_daily_profit, Max_daily_Loss
    return (Max_daily_profit + 0) > 0 || (Max_daily_Loss + 0) < 0
}

CheckMaxDailyPnlAtSessionEnd() {
    global Max_daily_profit, Max_daily_Loss, dailyPnlLimitTriggered
    if (dailyPnlLimitTriggered)
        return true
    if (!KalshiDailyPnlLimitsEnabled() || KalshiHasOpenOrUnsettledExposure())
        return false

    livePnl := ComputeKalshiLivePnl()
    if (livePnl = "")
        return false

    limitName := ""
    limitValue := ""
    if ((Max_daily_profit + 0) > 0 && livePnl >= (Max_daily_profit + 0)) {
        limitName := "Max_daily_profit"
        limitValue := Max_daily_profit + 0
    } else if ((Max_daily_Loss + 0) < 0 && livePnl <= (Max_daily_Loss + 0)) {
        limitName := "Max_daily_Loss"
        limitValue := Max_daily_Loss + 0
    }
    if (limitName = "")
        return false

    dailyPnlLimitTriggered := true
    UpdateKalshiPnlLogStreams()
    Log("Agent daily PnL limit reached | " limitName "=" FmtPnl(limitValue) " | agent PnL=" FmtPnl(livePnl) " | no active positions | stopping script")
    stopCode()
    return true
}

UpdateKalshiPnlLogStreams() {
    global kalshiWins, kalshiTradeCount, balanceRefreshMs
    LogStream("LIVE PNL", FmtPnl(ComputeKalshiLivePnl()))
    LogStream("WINS", kalshiWins "/" kalshiTradeCount)
    availableCredit := ns_ai_refresh_balance_logstream(balanceRefreshMs)
    if (availableCredit != "")
        LogStream("CREDITS", availableCredit)
}

PlaceKalshiOrder(action, marketTicker, side, price, size, clientOrderId := "", exchangeIndex := -1) {
    global enableLiveOrders, kalshiApiKeyId, kalshiPrivateKeyPath, restDelay, entryDiff, exitDiff, kalshiLastOrderResult
    exchangeIndex := NormalizeKalshiExchangeIndex(exchangeIndex)
    kalshiLastOrderResult := { action: action, ticker: marketTicker, exchangeIndex: exchangeIndex, side: side, apiAction: "", apiSide: "", cents: "", price: "", contractCents: "", fillPrice: "", fillSummary: NewKalshiFillSummary(), positionSize: "", timeInForce: "", size: size, status: "", body: "", orderId: "", clientOrderId: clientOrderId, reason: "not submitted" }

    if (!enableLiveOrders) {
        kalshiLastOrderResult.reason := "live orders disabled"
        return true
    }

    if (kalshiApiKeyId = "" || kalshiPrivateKeyPath = "") {
        kalshiLastOrderResult.reason := "missing API credentials"
        return false
    }

    if (marketTicker = "") {
        kalshiLastOrderResult.reason := "missing market ticker"
        return false
    }

    isBuy := (ToLower(action) = "buy")
    contractPrice := price + 0
    if (isBuy)
        contractPrice := contractPrice + entryDiff
    else
        contractPrice := 0.01
    contractCents := KalshiClampCents(Round(contractPrice * 100))
    apiAction := ToLower(action)
    apiSide := KalshiEventOrderSide(apiAction, side)
    apiCents := KalshiEventOrderCents(apiAction, side, contractCents)
    priceText := KalshiFixedPriceFromCents(apiCents)
    countText := KalshiFixedCount(size)
    timeInForce := isBuy ? "good_till_canceled" : "immediate_or_cancel"
    reduceOnly := isBuy ? "false" : "true"
    if (clientOrderId = "")
        clientOrderId := BuildClientOrderId(marketTicker, apiAction, apiSide)
    kalshiLastOrderResult.apiAction := apiAction
    kalshiLastOrderResult.apiSide := apiSide
    kalshiLastOrderResult.cents := apiCents
    kalshiLastOrderResult.price := priceText
    kalshiLastOrderResult.contractCents := contractCents
    kalshiLastOrderResult.timeInForce := timeInForce
    kalshiLastOrderResult.clientOrderId := clientOrderId

    payload := "{"
        . """ticker"":""" marketTicker ""","
        . """side"":""" apiSide ""","
        . """count"":""" countText ""","
        . """price"":""" priceText ""","
        . """time_in_force"":""" timeInForce ""","
        . """self_trade_prevention_type"":""taker_at_cross"","
        . """post_only"":false,"
        . """cancel_order_on_pause"":false,"
        . """reduce_only"":" reduceOnly ","
        . """exchange_index"":" exchangeIndex ","
        . """client_order_id"":""" clientOrderId """"
        . "}"

    res := KalshiSignedRequest("POST", "/trade-api/v2/portfolio/events/orders", payload)
    if !IsObject(res) {
        kalshiLastOrderResult.fatal := true
        kalshiLastOrderResult.reason := "order submission outcome unknown"
        Log("ERROR: " marketTicker " Order submission returned no response. Stopping to prevent an ambiguous order from being duplicated.")
        stopCode()
        return false
    }

    kalshiLastOrderResult.status := res.status
    kalshiLastOrderResult.body := res.body

    orderId := JsonField(res.body, "order_id")
    kalshiLastOrderResult.orderId := orderId
    responseFillCount := JsonField(res.body, "fill_count")
    responseAverageFillPrice := JsonField(res.body, "average_fill_price")
    if (IsNumericStr(responseFillCount) && (responseFillCount + 0) > 0 && IsNumericStr(responseAverageFillPrice)) {
        contractFillPrice := (side = "UP") ? responseAverageFillPrice + 0 : 1 - (responseAverageFillPrice + 0)
        if (contractFillPrice > 0 && contractFillPrice < 1) {
            kalshiLastOrderResult.fillPrice := contractFillPrice
            responseSummary := NewKalshiFillSummary()
            responseSummary.size := responseFillCount + 0
            responseSummary.price := contractFillPrice
            responseSummary.notional := contractFillPrice * responseSummary.size
            responseAverageFee := JsonField(res.body, "average_fee_paid")
            responseSummary.feesKnown := IsNumericStr(responseAverageFee)
            responseSummary.fees := responseSummary.feesKnown ? (responseAverageFee + 0) * responseSummary.size : 0
            responseSummary.source := "Kalshi order response"
            kalshiLastOrderResult.fillSummary := responseSummary
        }
    }

    if (res.status = 401 || res.status = 403) {
        kalshiLastOrderResult.reason := "auth rejected"
        return false
    }

    if (res.status != 201 && res.status != 200) {
        if (res.status >= 500) {
            kalshiLastOrderResult.fatal := true
            kalshiLastOrderResult.reason := "order submission outcome ambiguous (HTTP " res.status ")"
            Log("ERROR: " marketTicker " Kalshi returned HTTP " res.status " for order submission. Stopping because execution status is ambiguous.")
            stopCode()
            return false
        }
        kalshiLastOrderResult.reason := "order rejected"
        return false
    }

    if (orderId = "") {
        kalshiLastOrderResult.fatal := true
        kalshiLastOrderResult.reason := "accepted order response missing order ID"
        Log("ERROR: " marketTicker " Kalshi accepted an order without returning an order ID. Stopping because fills cannot be reconciled safely.")
        stopCode()
        return false
    }

    kalshiLastOrderResult.reason := "order accepted"

    if (isBuy)
        Sleep %restDelay%
    else
        Sleep 150

    if (isBuy && orderId != "") {
        remainingBefore := GetKalshiOrderRemainingCount(orderId, remainingQueryOk, exchangeIndex)
        cancelNeeded := !remainingQueryOk || remainingBefore > 0.000001
        if (cancelNeeded) {
            cancelConfirmed := CancelKalshiOrder(orderId, exchangeIndex)
            Sleep 500
            remainingAfter := GetKalshiOrderRemainingCount(orderId, remainingAfterQueryOk, exchangeIndex)
            remainderClosed := (remainingAfterQueryOk && remainingAfter <= 0.000001) || cancelConfirmed
            if (!remainderClosed) {
                kalshiLastOrderResult.fatal := true
                kalshiLastOrderResult.reason := "entry remainder cancellation could not be verified"
                Log("ERROR: " marketTicker " Entry order may still be resting. Verify/cancel order " orderId " in Kalshi.")
                stopCode()
                return false
            }
        }
    }

    positionSize := GetKalshiPositionSize(marketTicker, 3, exchangeIndex)
    if (positionSize = "") {
        kalshiLastOrderResult.fatal := true
        kalshiLastOrderResult.reason := "position confirmation unavailable"
        Log("ERROR: " marketTicker " Position could not be verified after order " orderId ". Stopping to prevent duplicate orders and inaccurate PnL.")
        stopCode()
        return false
    }
    responseFillSummary := kalshiLastOrderResult.fillSummary
    if (isBuy && positionSize <= 0 && IsObject(responseFillSummary) && responseFillSummary.size > 0) {
        Loop, 3 {
            Log("WARN: " marketTicker " Entry fills reported but position is not visible; retry " A_Index "/3 in 2 seconds")
            Sleep 2000
            positionSize := GetKalshiPositionSize(marketTicker, 3, exchangeIndex)
            if (positionSize != "" && positionSize > 0) {
                Log(marketTicker " Position verified on retry " A_Index "/3 | size " KalshiFormatSize(positionSize))
                break
            }
        }
        if (positionSize = "" || positionSize <= 0) {
            kalshiLastOrderResult.fatal := true
            kalshiLastOrderResult.reason := "reported entry fills not visible in position"
            Log("ERROR: " marketTicker " Kalshi reported entry fills, but the resulting position could not be verified. Stopping to prevent duplicate orders.")
            stopCode()
            return false
        }
    }
    hasPos := positionSize > 0
    kalshiLastOrderResult.positionSize := positionSize
    kalshiLastOrderResult.positionOpen := hasPos ? "yes" : "no"

    if (isBuy && !hasPos && orderId != "")
        kalshiLastOrderResult.reason := "not filled; resting order closed"

    if (isBuy) {
        if (hasPos && kalshiLastOrderResult.reason = "order accepted")
            kalshiLastOrderResult.reason := "position confirmed"
        else if (!hasPos && kalshiLastOrderResult.reason = "order accepted")
            kalshiLastOrderResult.reason := "position not confirmed"
    } else {
        if (hasPos)
            kalshiLastOrderResult.reason := "position still open after IoC sell"
        else
            kalshiLastOrderResult.reason := "position closed"
    }

    if (orderId != "") {
        apiFillSummary := GetKalshiOrderFillSummary(orderId, side, 2)
        currentFillSummary := kalshiLastOrderResult.fillSummary
        if (KalshiFillSummaryReady(apiFillSummary) && (!KalshiFillSummaryReady(currentFillSummary) || apiFillSummary.size >= (currentFillSummary.size - 0.000001)))
            kalshiLastOrderResult.fillSummary := apiFillSummary
    }

    if (isBuy && hasPos) {
        currentFillSummary := kalshiLastOrderResult.fillSummary
        if (!IsObject(currentFillSummary) || currentFillSummary.size < (positionSize - 0.000001)) {
            if !IsObject(currentFillSummary)
                currentFillSummary := NewKalshiFillSummary()
            currentFillSummary.feesKnown := false
            currentFillSummary.source := "incomplete entry fills"
            kalshiLastOrderResult.fillSummary := currentFillSummary
        }
    }

    return (isBuy ? hasPos : !hasPos)
}

KalshiEventOrderSide(apiAction, contractSide) {
    if (apiAction = "buy")
        return (contractSide = "UP") ? "bid" : "ask"
    return (contractSide = "UP") ? "ask" : "bid"
}

KalshiEventOrderCents(apiAction, contractSide, contractCents) {
    contractCents := KalshiClampCents(contractCents)
    if (contractSide = "UP")
        return contractCents
    return KalshiClampCents(100 - contractCents)
}

KalshiClampCents(cents) {
    cents := Round(cents + 0)
    if (cents < 1)
        return 1
    if (cents > 99)
        return 99
    return cents
}

KalshiFixedPriceFromCents(cents) {
    cents := KalshiClampCents(cents)
    return "0." KalshiPad2(cents) "00"
}

KalshiFixedCount(size) {
    countCents := Round((size + 0) * 100)
    whole := Floor(countCents / 100)
    frac := Mod(countCents, 100)
    return whole "." KalshiPad2(frac)
}

KalshiPad2(n) {
    n := Round(n + 0)
    if (n < 10)
        return "0" n
    return n
}

KalshiLastOrderApiSummary() {
    global kalshiLastOrderResult
    if !IsObject(kalshiLastOrderResult)
        return "API no order attempt recorded"

    action := KalshiResultValue(kalshiLastOrderResult, "action", "ORDER")
    side := KalshiResultValue(kalshiLastOrderResult, "side", "")
    apiSide := KalshiResultValue(kalshiLastOrderResult, "apiSide", "")
    ticker := KalshiResultValue(kalshiLastOrderResult, "ticker", "")
    exchangeIndex := KalshiResultValue(kalshiLastOrderResult, "exchangeIndex", "")
    cents := KalshiResultValue(kalshiLastOrderResult, "cents", "")
    price := KalshiResultValue(kalshiLastOrderResult, "price", "")
    contractCents := KalshiResultValue(kalshiLastOrderResult, "contractCents", "")
    timeInForce := KalshiResultValue(kalshiLastOrderResult, "timeInForce", "")
    size := KalshiResultValue(kalshiLastOrderResult, "size", "")
    status := KalshiResultValue(kalshiLastOrderResult, "status", "")
    body := KalshiResultValue(kalshiLastOrderResult, "body", "")
    orderId := KalshiResultValue(kalshiLastOrderResult, "orderId", "")
    clientOrderId := KalshiResultValue(kalshiLastOrderResult, "clientOrderId", "")
    reason := KalshiResultValue(kalshiLastOrderResult, "reason", "")

    orderText := action
    if (side != "")
        orderText .= " " side
    if (apiSide != "")
        orderText .= " -> " apiSide
    if (ticker != "")
        orderText .= " " ticker
    if (exchangeIndex != "")
        orderText .= " shard=" exchangeIndex
    if (price != "")
        orderText .= " @" price
    else if (cents != "")
        orderText .= " @" cents "c"
    if (size != "")
        orderText .= " x" size
    if (timeInForce != "")
        orderText .= " " timeInForce
    if (contractCents != "" && contractCents != cents)
        orderText .= " contract@" contractCents "c"

    apiText := (status = "") ? "API no response" : "API HTTP " status
    includeBody := (status != 200 && status != 201)
    apiMessage := KalshiApiMessage(body, includeBody)
    if (apiMessage != "")
        apiText .= " " apiMessage
    if (orderId != "")
        apiText .= " order_id=" KalshiShortLogText(orderId, 28)
    if (reason != "")
        apiText .= " | " reason
    if (clientOrderId != "")
        apiText .= " | cid=" KalshiShortLogText(clientOrderId, 36)

    return orderText " | " apiText
}

KalshiApiMessage(body, includeBodyFallback := true) {
    body := Trim(body)
    if (body = "")
        return ""
    code := JsonField(body, "code")
    message := JsonField(body, "message")
    detail := JsonField(body, "detail")
    errorText := JsonField(body, "error")
    if (code != "" && message != "")
        return "code=" KalshiCompactLogText(code, 40) " msg=" KalshiCompactLogText(message, 140)
    if (message != "")
        return "msg=" KalshiCompactLogText(message, 160)
    if (detail != "")
        return "detail=" KalshiCompactLogText(detail, 160)
    if (errorText != "")
        return "error=" KalshiCompactLogText(errorText, 160)
    if (includeBodyFallback)
        return "body=" KalshiCompactLogText(body, 180)
    return ""
}

KalshiResultValue(result, key, fallback := "") {
    if IsObject(result) && result.HasKey(key)
        return result[key]
    return fallback
}

KalshiShortLogText(s, maxLen := 36) {
    return KalshiCompactLogText(s, maxLen)
}

KalshiCompactLogText(s, maxLen := 160) {
    s := Trim(JsonUnescape(s))
    s := StrReplace(s, "`r", " ")
    s := StrReplace(s, "`n", " ")
    s := StrReplace(s, A_Tab, " ")
    s := RegExReplace(s, "\s+", " ")
    if (StrLen(s) > maxLen)
        return SubStr(s, 1, maxLen - 3) "..."
    return s
}

NormalizeKalshiExchangeIndex(exchangeIndex) {
    exchangeIndex := Trim(exchangeIndex)
    if !RegExMatch(exchangeIndex, "^-?\d+$")
        return -1
    exchangeIndex += 0
    return (exchangeIndex >= -1) ? exchangeIndex : -1
}

KalshiBalanceDollarsFromBody(body) {
    balanceDollars := JsonField(body, "balance_dollars")
    if !IsNumericStr(balanceDollars)
        return ""
    return balanceDollars + 0
}

GetKalshiBalanceSnapshot(exchangeIndex := "", maxAttempts := 1, forceRefresh := false) {
    global kalshiAggregateBalanceSnapshot
    snapshot := { ok: false, balance: "", status: "", body: "", userMissing: false, retryable: true, balances: {} }
    endpoint := "/trade-api/v2/portfolio/balance"
    if (exchangeIndex != "") {
        exchangeIndex := NormalizeKalshiExchangeIndex(exchangeIndex)
        if (exchangeIndex < 0) {
            snapshot.retryable := false
            return snapshot
        }
        endpoint .= "?exchange_index=" exchangeIndex
    }

    ; Startup and funding checks share the same short-lived aggregate read.
    if (!forceRefresh && IsObject(kalshiAggregateBalanceSnapshot) && (A_TickCount - kalshiAggregateBalanceSnapshot.tick) < 1100) {
        if (exchangeIndex = "")
            return kalshiAggregateBalanceSnapshot.Clone()
        if kalshiAggregateBalanceSnapshot.balances.HasKey(exchangeIndex) {
            snapshot.ok := true
            snapshot.status := 200
            snapshot.balance := kalshiAggregateBalanceSnapshot.balances[exchangeIndex]
            return snapshot
        }
    }

    attempt := 1
    while (attempt <= maxAttempts) {
        ; KalshiSignedRequest paces every balance GET, including scoped reads.
        res := KalshiSignedRequest("GET", endpoint)
        if IsObject(res) {
            snapshot.status := res.status
            snapshot.body := res.body
            snapshot.retryable := (res.status = 0 || res.status = 200 || res.status = 408 || res.status = 429 || res.status >= 500)
            if (res.status = 200) {
                balanceDollars := KalshiBalanceDollarsFromBody(res.body)
                if (balanceDollars != "") {
                    snapshot.ok := true
                    snapshot.balance := balanceDollars + 0
                    snapshot.tick := A_TickCount
                    if (exchangeIndex = "") {
                        snapshot.balances := KalshiBalanceBreakdown(res.body)
                        kalshiAggregateBalanceSnapshot := snapshot.Clone()
                    }
                    return snapshot
                }
            }

            errorCode := JsonField(res.body, "code")
            if (exchangeIndex != "" && InStr(errorCode, "user_not_found") = 1) {
                snapshot.ok := true
                snapshot.balance := 0
                snapshot.userMissing := true
                return snapshot
            }
            if (!snapshot.retryable)
                break
        }
        ; The shared request scheduler supplies spacing and exponential backoff.
        attempt++
    }
    return snapshot
}

KalshiBalanceBreakdown(body) {
    balances := {}
    if !RegExMatch(body, """balance_breakdown""\s*:\s*\[([^\]]*)\]", breakdown)
        return balances
    pos := 1
    while (pos := RegExMatch(breakdown1, "\{[^{}]*\}", item, pos)) {
        exchangeIndex := JsonField(item, "exchange_index")
        balance := JsonField(item, "balance") ; breakdown balances are dollar strings
        if (RegExMatch(exchangeIndex, "^\d+$") && IsNumericStr(balance))
            balances[exchangeIndex + 0] := balance + 0
        pos += StrLen(item)
    }
    return balances
}

KalshiBalanceForShard(aggregate, exchangeIndex) {
    if (IsObject(aggregate) && aggregate.ok && aggregate.balances.HasKey(exchangeIndex))
        return { ok: true, balance: aggregate.balances[exchangeIndex], status: 200 }
    ; Older responses or an unprovisioned shard may have no breakdown entry.
    return GetKalshiBalanceSnapshot(exchangeIndex, 1)
}

KalshiFundingReadFailed(asset, exchangeIndex, snapshot, state, ByRef permanentFailure) {
    permanentFailure := IsObject(snapshot) && !snapshot.retryable
    if (permanentFailure)
        state.status := "FAILED"
    status := (IsObject(snapshot) && snapshot.status != "") ? snapshot.status : "no response"
    ns_log_once(asset, "FUNDING_READ_" exchangeIndex "_" status, asset " Balance read " (permanentFailure ? "rejected" : "unavailable; will retry") " | shard " exchangeIndex " | HTTP " status)
    return false
}

EnsureKalshiShardFunding(asset, destinationExchangeIndex, ByRef permanentFailure := false) {
    global enableLiveOrders, kalshiShardFundingSessionStatus, kalshiShardPendingTransfers
    global kalshiBalanceNextRequestTick, kalshiAggregateBalanceSnapshot
    permanentFailure := false
    if (!enableLiveOrders)
        return true

    destinationExchangeIndex := NormalizeKalshiExchangeIndex(destinationExchangeIndex)
    if (destinationExchangeIndex = 0)
        return true
    if (destinationExchangeIndex != 2) {
        permanentFailure := true
        ns_log_once(asset, "INVALID_SHARD", "ERROR: " asset " Market provided unsupported exchange shard " destinationExchangeIndex "; expected shard 0 or 2")
        return false
    }

    ; Consolidate exchange 0 into exchange 2 only once during this script run.
    ; A temporary balance error must not permanently cache a failed transfer.
    fundingTransferKey := "0>2"
    if !kalshiShardFundingSessionStatus.HasKey(fundingTransferKey)
        kalshiShardFundingSessionStatus[fundingTransferKey] := { status: "WAIT_FUNDING", retryTick: 0 }
    state := kalshiShardFundingSessionStatus[fundingTransferKey]
    if (state.status = "READY")
        return true
    if (state.status = "FAILED") {
        permanentFailure := true
        return false
    }
    if (A_TickCount < state.retryTick)
        return false

    ; Defer in the strategy loop instead of blocking other assets during backoff.
    cacheFresh := IsObject(kalshiAggregateBalanceSnapshot) && (A_TickCount - kalshiAggregateBalanceSnapshot.tick) < 1100
    if (A_TickCount < kalshiBalanceNextRequestTick && (!cacheFresh || kalshiShardPendingTransfers.HasKey(2)))
        return false
    Random, fundingJitter, 0, 500
    state.retryTick := A_TickCount + 5000 + fundingJitter

    ; Retain the same transfer across asset retries and market/session changes.
    if kalshiShardPendingTransfers.HasKey(2)
        return ReconcileKalshiShardTransfer(asset, 2, state, permanentFailure)

    aggregate := GetKalshiBalanceSnapshot("", 1)
    if (!aggregate.ok)
        return KalshiFundingReadFailed(asset, "all", aggregate, state, permanentFailure)
    source := KalshiBalanceForShard(aggregate, 0)
    if (!source.ok)
        return KalshiFundingReadFailed(asset, 0, source, state, permanentFailure)

    ; The API uses centicents. Floor to avoid transferring more than is available.
    transferCenticents := Floor(((source.balance + 0) * 10000) + 0.000001)
    if (transferCenticents <= 0) {
        state.status := "READY"
        return true
    }
    transferDollars := transferCenticents / 10000.0
    destination := KalshiBalanceForShard(aggregate, 2)
    if (!destination.ok)
        return KalshiFundingReadFailed(asset, 2, destination, state, permanentFailure)
    confirmationTargetDollars := (destination.balance + 0) + transferDollars

    clientTransferId := NewKalshiTransferId()
    if (clientTransferId = "") {
        state.status := "FAILED"
        permanentFailure := true
        Log("ERROR: " asset " Could not create a duplicate-prevention ID for the shard transfer")
        return false
    }
    payload := "{"
        . """source"":""event_contract"","
        . """destination"":""event_contract"","
        . """client_transfer_id"":""" clientTransferId ""","
        . """amount"":" transferCenticents ","
        . """source_exchange_shard"":0,"
        . """destination_exchange_shard"":2,"
        . """source_subaccount"":0,"
        . """destination_subaccount"":0"
        . "}"
    pending := { transferId: "", clientTransferId: clientTransferId, payload: payload, historyCursor: "", attempted: false, transferDollars: transferDollars, targetDollars: confirmationTargetDollars }
    ; Store before POST: a timeout may occur after Kalshi accepted the transfer.
    kalshiShardPendingTransfers[2] := pending
    return SubmitKalshiShardTransfer(asset, 2, state, pending, permanentFailure)
}

SubmitKalshiShardTransfer(asset, exchangeIndex, state, pending, ByRef permanentFailure) {
    global kalshiShardPendingTransfers
    wasAttempted := pending.attempted
    pending.attempted := true
    res := KalshiSignedRequest("POST", "/trade-api/v2/portfolio/intra_exchange_instance_transfer", pending.payload)
    if (IsObject(res) && res.status = 200) {
        pending.transferId := JsonField(res.body, "transfer_id")
        Log(asset " One-time exchange 0 -> 2 transfer requested | $" FmtMoney(pending.transferDollars) " | client_transfer_id=" pending.clientTransferId " | transfer_id=" pending.transferId)
    } else if (IsObject(res) && (res.status = 401 || res.status = 403)) {
        if (!wasAttempted)
            kalshiShardPendingTransfers.Delete(exchangeIndex)
        state.status := "FAILED"
        permanentFailure := true
        Log("ERROR: " asset " Exchange 0 -> 2 transfer unauthorized | HTTP " res.status " " KalshiApiMessage(res.body))
    } else if (!IsObject(res) || res.status = 0 || res.status = 408 || res.status = 409 || res.status >= 500 || wasAttempted) {
        ; Any retry keeps the exact payload and client ID, including after a 409.
        ns_log_once(asset, "TRANSFER_AMBIGUOUS_" pending.clientTransferId, asset " Transfer outcome pending; will reconcile before another transfer")
    } else {
        ; A definitive first rejection did not create a transfer.
        kalshiShardPendingTransfers.Delete(exchangeIndex)
        permanentFailure := (res.status != 429 && !InStr(JsonField(res.body, "code"), "insufficient"))
        if (permanentFailure)
            state.status := "FAILED"
        ns_log_once(asset, "TRANSFER_REJECTED_" res.status, asset " Exchange 0 -> 2 transfer rejected | HTTP " res.status " " KalshiApiMessage(res.body) (permanentFailure ? "" : " | will retry"))
    }
    return false
}

ReconcileKalshiShardTransfer(asset, exchangeIndex, state, ByRef permanentFailure) {
    global kalshiShardPendingTransfers
    pending := kalshiShardPendingTransfers[exchangeIndex]
    aggregate := GetKalshiBalanceSnapshot("", 1, true)
    if (!aggregate.ok)
        return KalshiFundingReadFailed(asset, "all", aggregate, state, permanentFailure)
    destination := KalshiBalanceForShard(aggregate, exchangeIndex)
    if (!destination.ok)
        return KalshiFundingReadFailed(asset, exchangeIndex, destination, state, permanentFailure)

    transferComplete := false
    historyExhausted := false
    if (pending.transferId != "") {
        res := KalshiSignedRequest("GET", "/trade-api/v2/portfolio/intra_exchange_instance_transfers/" KalshiQueryEncode(pending.transferId))
        if (IsObject(res) && res.status = 200)
            transferComplete := (JsonField(res.body, "status") = "complete")
    } else {
        ; Recover a lost POST response by its client ID. Scan one page per retry.
        endpoint := "/trade-api/v2/portfolio/intra_exchange_instance_transfers?limit=100"
        if (pending.historyCursor != "")
            endpoint .= "&cursor=" KalshiQueryEncode(pending.historyCursor)
        res := KalshiSignedRequest("GET", endpoint)
        if (IsObject(res) && res.status = 200) {
            pos := 1
            while (pos := RegExMatch(res.body, "\{[^{}]*\}", item, pos)) {
                if (JsonField(item, "client_transfer_id") = pending.clientTransferId) {
                    pending.transferId := JsonField(item, "transfer_id")
                    transferComplete := (JsonField(item, "status") = "complete")
                    break
                }
                pos += StrLen(item)
            }
            pending.historyCursor := JsonField(res.body, "cursor")
            historyExhausted := (pending.transferId = "" && pending.historyCursor = "")
        }
    }

    ; A completed transfer remains one-time even if another bot has spent funds
    ; before this balance read. Order submission still enforces available funds.
    if (transferComplete)
        kalshiShardPendingTransfers.Delete(exchangeIndex)
    targetReached := (destination.balance + 0) >= (pending.targetDollars - 0.000001)
    if (transferComplete || targetReached) {
        state.status := "READY"
        Log(asset " One-time exchange 0 -> 2 transfer confirmed | $" FmtMoney(destination.balance) " available on exchange 2")
        return true
    }
    if (historyExhausted) {
        ; Kalshi deduplicates this UUID. Reuse only the exact original request.
        return SubmitKalshiShardTransfer(asset, exchangeIndex, state, pending, permanentFailure)
    }
    ns_log_once(asset, "TRANSFER_PENDING_" pending.clientTransferId, asset " Transfer pending confirmation; will retry without creating another transfer")
    return false
}

NewKalshiTransferId() {
    VarSetCapacity(guid, 16, 0)
    if (DllCall("ole32\CoCreateGuid", "Ptr", &guid) != 0)
        return ""
    VarSetCapacity(guidText, 78, 0)
    if (!DllCall("ole32\StringFromGUID2", "Ptr", &guid, "Ptr", &guidText, "Int", 39))
        return ""
    return Trim(StrGet(&guidText, "UTF-16"), "{}")
}

KalshiScheduleNextBalanceRead(status) {
    global kalshiBalanceNextRequestTick, kalshiBalanceRetryCount
    delayMs := 1100
    if (status = 0 || status = 408 || status = 429 || status >= 500) {
        kalshiBalanceRetryCount := Min(kalshiBalanceRetryCount + 1, 5)
        Random, balanceJitter, 0, 250
        delayMs := (1100 * (2 ** (kalshiBalanceRetryCount - 1))) + balanceJitter
        if (status = 429)
            Log("Balance read rate-limited; retrying after " Round(delayMs / 1000.0, 2) " seconds")
    } else {
        kalshiBalanceRetryCount := 0
    }
    kalshiBalanceNextRequestTick := A_TickCount + delayMs
}

CancelKalshiOrder(orderId, exchangeIndex := -1) {
    if (orderId = "")
        return false
    exchangeIndex := NormalizeKalshiExchangeIndex(exchangeIndex)
    res := KalshiSignedRequest("DELETE", "/trade-api/v2/portfolio/events/orders/" orderId "?exchange_index=" exchangeIndex)
    return IsObject(res) && (res.status = 200 || res.status = 204)
}

GetKalshiOrderRemainingCount(orderId, ByRef queryOk, exchangeIndex := -1) {
    queryOk := false
    if (orderId = "")
        return ""
    exchangeIndex := NormalizeKalshiExchangeIndex(exchangeIndex)
    res := KalshiSignedRequest("GET", "/trade-api/v2/portfolio/orders/" orderId "?exchange_index=" exchangeIndex)
    if !IsObject(res) || (res.status != 200)
        return ""
    remaining := GetFirstNonEmptyJsonField(res.body, ["remaining_count_fp", "remaining_count"])
    if (!IsNumericStr(remaining))
        return ""
    queryOk := true
    return remaining + 0
}

LoadKalshiCredentialsFromFiles() {
    global kalshiApiKeyId, kalshiApiKeyFile, kalshiPrivateKeyPath, kalshiPrivateKeyFile, kalshiApiKeyResolvedPath, kalshiPrivateKeyResolvedPath

    kalshiApiKeyId := ""
    kalshiApiKeyResolvedPath := ResolveCredentialPath(kalshiApiKeyFile)
    if (kalshiApiKeyResolvedPath != "") {
        FileRead, apiRaw, %kalshiApiKeyResolvedPath%
        apiCode := JsonField(apiRaw, "code")
        if (apiCode != "")
            kalshiApiKeyId := Trim(JsonUnescape(apiCode))
    }

    kalshiPrivateKeyPath := ""
    kalshiPrivateKeyResolvedPath := ResolveCredentialPath(kalshiPrivateKeyFile)
    if (kalshiPrivateKeyResolvedPath != "") {
        FileRead, keyRaw, %kalshiPrivateKeyResolvedPath%
        keyCode := JsonField(keyRaw, "code")
        if (keyCode != "") {
            pemText := JsonUnescape(keyCode)
            tempBase := A_Temp
            if (tempBase = "")
                tempBase := A_ScriptDir
            tempPem := tempBase "\kalshi_ahk\privatekey_runtime.pem"
            FileCreateDir, % tempBase "\kalshi_ahk"
            FileDelete, %tempPem%
            FileAppend, %pemText%, %tempPem%
            kalshiPrivateKeyPath := tempPem
        }
    }
}

StartupCredentialCheck() {
    global kalshiApiKeyId, kalshiPrivateKeyPath, kalshiSignerPath

    apiReady := (kalshiApiKeyId != "")
    keyReady := (kalshiPrivateKeyPath != "" && FileExist(kalshiPrivateKeyPath))
    signerOut := RunAndCapture(QuoteForCmd(kalshiSignerPath) " version")
    signerReady := InStr(signerOut, "NightShark Signer")

    if (apiReady && keyReady && signerReady) {
        snapshot := GetKalshiBalanceSnapshot("", 3, true)
        if (snapshot.ok) {
            Log("Credentials processed successfully | aggregate balance $" FmtMoney(snapshot.balance))
            return true
        }
        if (snapshot.status = 401 || snapshot.status = 403) {
            Log("ERROR: API key or private key is incorrect (HTTP " snapshot.status ")")
            Log("Please fix your API key / private key and restart.")
        } else {
            Log("ERROR: Startup balance unavailable after retries | HTTP " snapshot.status " | stopping before live trading")
        }
        stopCode()
        return false
    }

    if (!apiReady)
        Log("ERROR: API key not loaded")
    if (!keyReady)
        Log("ERROR: Private key not loaded")
    if (!signerReady)
        Log("ERROR: NightShark signer not found")
    Log("Please fix API credentials. Stopping script.")
    stopCode()
    return false
}

ResolveCredentialPath(pathSpec) {
    if (pathSpec = "")
        return ""
    if FileExist(pathSpec)
        return pathSpec
    normalized := StrReplace(pathSpec, "\", "/")
    if FileExist(normalized)
        return normalized
    relative := normalized
    while (SubStr(relative, 1, 1) = "/" || SubStr(relative, 1, 1) = "\")
        relative := SubStr(relative, 2)
    fromScriptDir := A_ScriptDir "/" relative
    if FileExist(fromScriptDir)
        return fromScriptDir
    fromScriptDirBackslash := StrReplace(fromScriptDir, "/", "\")
    if FileExist(fromScriptDirBackslash)
        return fromScriptDirBackslash
    return ""
}

JsonUnescape(s) {
    s := StrReplace(s, "\/", "/")
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\t", A_Tab)
    s := StrReplace(s, Chr(92) Chr(34), Chr(34))
    s := StrReplace(s, Chr(92) Chr(92), Chr(92))
    return s
}

KalshiSignedRequest(method, endpointPath, bodyJson := "") {
    global kalshiApiBase, kalshiApiKeyId, kalshiBalanceNextRequestTick, kalshiAggregateBalanceSnapshot
    isBalanceRead := (method = "GET" && RegExMatch(endpointPath, "^/trade-api/v2/portfolio/balance(?:\?|$)"))
    if (isBalanceRead) {
        waitMs := kalshiBalanceNextRequestTick - A_TickCount
        if (waitMs > 0)
            Sleep %waitMs%
        kalshiAggregateBalanceSnapshot := ""
    } else if (method != "GET") {
        kalshiAggregateBalanceSnapshot := ""
    }
    ; Sign after waiting, so the timestamp stays fresh during a rate-limit backoff.
    timestamp := CurrentTimeMillis()
    signPath := endpointPath
    if InStr(signPath, "?")
        signPath := SubStr(signPath, 1, InStr(signPath, "?") - 1)

    signature := SignKalshiMessage(timestamp method signPath)
    if (signature = "")
        return false

    url := kalshiApiBase endpointPath
    global httpSignedObj
    if !IsObject(httpSignedObj)
        httpSignedObj := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    http := httpSignedObj
    http.Option(9) := 2048 | 8192
    http.Open(method, url, false)
    http.SetTimeouts(1000, 1000, 3000, 5000)
    http.SetRequestHeader("User-Agent", "Mozilla/5.0")
    http.SetRequestHeader("Cache-Control", "no-cache, no-store")
    http.SetRequestHeader("Pragma", "no-cache")
    http.SetRequestHeader("KALSHI-ACCESS-KEY", kalshiApiKeyId)
    http.SetRequestHeader("KALSHI-ACCESS-TIMESTAMP", timestamp)
    http.SetRequestHeader("KALSHI-ACCESS-SIGNATURE", signature)
    http.SetRequestHeader("Content-Type", "application/json")

    try {
        if (bodyJson != "")
            http.Send(bodyJson)
        else
            http.Send()
    } catch e {
        httpSignedObj := ""
        if (isBalanceRead)
            KalshiScheduleNextBalanceRead(0)
        return false
    }

    res := { status: http.Status, body: http.ResponseText }
    if (isBalanceRead)
        KalshiScheduleNextBalanceRead(res.status)
    return res
}

SignKalshiMessage(message) {
    global kalshiPrivateKeyPath, kalshiKeyPassphrase, kalshiSignerPath
    if (kalshiPrivateKeyPath = "" || !FileExist(kalshiPrivateKeyPath))
        return ""
    passArg := ""
    if (kalshiKeyPassphrase != "")
        passArg := " --passphrase " QuoteForCmd(kalshiKeyPassphrase)
    signCmd := QuoteForCmd(kalshiSignerPath)
        . " sign --key "
        . QuoteForCmd(kalshiPrivateKeyPath)
        . " --message "
        . QuoteForCmd(message)
        . passArg
    out := Trim(RunAndCapture(signCmd))
    if (SubStr(out, 1, 6) = "ERROR:")
        return ""
    return out
}

BuildClientOrderId(ticker, action, side) {
    nowUtc := CurrentUtcNowAhk()
    if (nowUtc = "")
        nowUtc := A_Now
    Random, r, 100000, 999999
    marketToken := RegExReplace(ticker, "^KX([A-Z0-9]+)15M.*$", "$1")
    if (marketToken = ticker || marketToken = "")
        marketToken := SubStr(RegExReplace(ticker, "[^A-Za-z0-9]", ""), 1, 12)
    clientOrderId := marketToken "-" action "-" side "-" nowUtc "-" A_TickCount "-" r
    return SubStr(clientOrderId, 1, 64)
}

CurrentTimeMillis() {
    epoch := CurrentUtcNowAhk()
    if (epoch = "")
        return ""
    EnvSub, epoch, 19700101000000, Seconds
    return epoch * 1000
}

QuoteForCmd(s) {
    s := StrReplace(s, """", "\""")
    return """" s """"
}

RunAndCapture(command) {
    return RunCMD(command, A_ScriptDir)
}

ToLower(s) {
    StringLower, out, s
    return out
}

FindNightSharkSigner() {
    candidates := [ A_ScriptDir "\nightshark-signer.exe"
        , A_ScriptDir "/nightshark-signer.exe"
        , A_WorkingDir "\nightshark-signer.exe"
        , A_WorkingDir "/nightshark-signer.exe" ]
    for _, p in candidates {
        if FileExist(p)
            return p
    }
    return A_ScriptDir "\nightshark-signer.exe"
}

CanPlaceOrderNow(asset) {
    global enableLiveOrders, kalshiApiKeyId, kalshiPrivateKeyPath
    if (!enableLiveOrders)
        return true
    return (kalshiApiKeyId != "" && kalshiPrivateKeyPath != "" && FileExist(kalshiPrivateKeyPath))
}

; ==================== Market data and formatting helpers ====================
CurrentUtcNowAhk() {
    nowUtc := A_NowUTC
    if (nowUtc != "")
        return nowUtc

    out := Trim(RunCMD("powershell -NoProfile -Command ""[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')""", A_ScriptDir))
    if RegExMatch(out, "^\d{14}$")
        return out
    return ""
}

FormatAssetList(assetList) {
    if !IsObject(assetList)
        return ""
    assetText := ""
    for _, asset in assetList
        assetText .= (assetText = "" ? "" : ", ") asset
    return assetText
}

MinutesRemainingInQuarter() {
    utc := CurrentUtcNowAhk()
    if (utc = "") {
        currentMinute := A_Min + 0
        remaining := 15 - Mod(currentMinute, 15)
        return remaining - ((A_Sec + 0) / 60.0)
    }
    mm := SubStr(utc, 11, 2) + 0
    ss := SubStr(utc, 13, 2) + 0
    return 15 - Mod(mm, 15) - (ss / 60.0)
}

CurrentQuarterIndex() {
    utc := CurrentUtcNowAhk()
    if (utc = "") {
        totalMinutes := (A_Hour + 0) * 60 + (A_Min + 0)
        return Floor(totalMinutes / 15)
    }
    hh := SubStr(utc, 9, 2) + 0
    mm := SubStr(utc, 11, 2) + 0
    totalMinutes := hh * 60 + mm
    return Floor(totalMinutes / 15)
}

SnapshotMinutesLeft(snapshot) {
    if !IsObject(snapshot)
        return ""

    if (snapshot.HasKey("closeTime") && snapshot.closeTime != "") {
        minsLeft := MinutesUntilIsoUtc(snapshot.closeTime)
        if (minsLeft != "")
            return minsLeft
    }

    if (snapshot.HasKey("minutesLeft"))
        return snapshot.minutesLeft
    return ""
}

IsSnapshotExpired(snapshot, cutoffMinutes := 0) {
    minsLeft := SnapshotMinutesLeft(snapshot)
    return (minsLeft != "" && minsLeft <= cutoffMinutes)
}

ClearKalshiMarketCache(asset) {
    global assetSnapshotCache, assetMarketRefreshTick
    if (assetSnapshotCache.HasKey(asset))
        assetSnapshotCache.Delete(asset)
    if (assetMarketRefreshTick.HasKey(asset))
        assetMarketRefreshTick.Delete(asset)
}

GetKalshiMarketSnapshot(asset, maxRetries := 4) {
    global assetSeriesMap, assetSnapshotCache, assetMarketRefreshTick, marketRefreshMs
    if !assetSeriesMap.HasKey(asset)
        return false
    series := assetSeriesMap[asset]
    nowTick := A_TickCount

    if (assetSnapshotCache.HasKey(asset) && assetMarketRefreshTick.HasKey(asset)) {
        cached := assetSnapshotCache[asset]
        if (IsObject(cached) && (nowTick - assetMarketRefreshTick[asset]) < marketRefreshMs) {
            if (IsSnapshotExpired(cached, 0.5)) {
                ClearKalshiMarketCache(asset)
            } else {
                if (RefreshKalshiBestAsks(cached))
                    return cached
                return false
            }
        }
    }

    attempt := 1
    while (attempt <= maxRetries) {
        url := "https://api.elections.kalshi.com/trade-api/v2/markets?series_ticker=" series "&status=open&limit=1&_=" A_TickCount "-" attempt
        body := HttpGet(url)

        if (body != "") {
            marketTicker := GetFirstNonEmptyJsonField(body, ["ticker"])
            exchangeIndex := GetFirstNonEmptyJsonField(body, ["exchange_index"])
            yesPrice := GetKalshiDollarPrice(body, "yes_ask_dollars", "yes_ask")
            noPrice  := GetKalshiDollarPrice(body, "no_ask_dollars", "no_ask")
            yesBidPrice := GetKalshiDollarPrice(body, "yes_bid_dollars", "yes_bid")
            noBidPrice  := GetKalshiDollarPrice(body, "no_bid_dollars", "no_bid")
            yesBidSize := GetFirstNonEmptyJsonField(body, ["yes_bid_size_fp"])
            noBidSize  := GetFirstNonEmptyJsonField(body, ["no_bid_size_fp"])

            closeIso := GetFirstNonEmptyJsonField(body, ["close_time", "expected_expiration_time", "expiration_time", "settlement_time"])
            minsLeft := MinutesUntilIsoUtc(closeIso)

            ; Skip markets that already closed or close in < 30 seconds (stale/expired)
            if (minsLeft != "" && minsLeft < 0.5) {
                if (attempt < maxRetries) {
                    Sleep 200
                    attempt++
                    continue
                }
            }

            if (marketTicker != "") {
                obj := {}
                obj.up := (yesPrice != "") ? yesPrice + 0 : ""
                obj.down := (noPrice != "") ? noPrice + 0 : ""
                obj.upBid := (yesBidPrice != "") ? yesBidPrice + 0 : ""
                obj.downBid := (noBidPrice != "") ? noBidPrice + 0 : ""
                obj.upBidSize := IsNumericStr(yesBidSize) ? yesBidSize + 0 : ""
                obj.downBidSize := IsNumericStr(noBidSize) ? noBidSize + 0 : ""
                obj.minutesLeft := minsLeft
                obj.closeTime := closeIso
                obj.marketTicker := marketTicker
                obj.exchangeIndex := NormalizeKalshiExchangeIndex(exchangeIndex)
                assetSnapshotCache[asset] := obj
                assetMarketRefreshTick[asset] := nowTick
                if (RefreshKalshiBestAsks(obj) || (obj.up != "" && obj.down != ""))
                    return obj
            }
        }

        if (attempt < maxRetries)
            Sleep 200
        attempt++
    }

    if (assetSnapshotCache.HasKey(asset)) {
        cached := assetSnapshotCache[asset]
        if IsObject(cached) {
            if (IsSnapshotExpired(cached, 0.5)) {
                ClearKalshiMarketCache(asset)
                return false
            }
            if (RefreshKalshiBestAsks(cached))
                return cached
        }
    }
    return false
}

RefreshKalshiBestAsks(snapshot) {
    if !IsObject(snapshot) || snapshot.marketTicker = ""
        return false

    url := "https://api.elections.kalshi.com/trade-api/v2/markets/" snapshot.marketTicker "/orderbook?depth=1&_=" A_TickCount
    body := HttpGet(url)
    if (body = "")
        return false

    yesLevel := GetOrderbookBestLevel(body, "yes_dollars")
    noLevel := GetOrderbookBestLevel(body, "no_dollars")
    yesBid := IsObject(yesLevel) ? yesLevel.price : ""
    noBid := IsObject(noLevel) ? noLevel.price : ""
    updated := false
    ; Do not carry a stale liquidation mark when one side has no current bid.
    snapshot.upBid := ""
    snapshot.downBid := ""
    snapshot.upBidSize := ""
    snapshot.downBidSize := ""

    if (noBid != "") {
        snapshot.up := Round(1 - (noBid + 0), 4)
        snapshot.downBid := noBid + 0
        snapshot.downBidSize := noLevel.size + 0
        updated := true
    }
    if (yesBid != "") {
        snapshot.down := Round(1 - (yesBid + 0), 4)
        snapshot.upBid := yesBid + 0
        snapshot.upBidSize := yesLevel.size + 0
        updated := true
    }

    return updated
}

GetOrderbookBestLevel(json, sideField) {
    ; The request uses depth=1, so the sole returned pair is the executable top level.
    pattern := """" sideField """\s*:\s*\[\s*\[\s*""?(-?\d+(?:\.\d+)?)""?\s*,\s*""?(-?\d+(?:\.\d+)?)"
    if RegExMatch(json, pattern, m)
        return { price: m1 + 0, size: m2 + 0 }
    return ""
}

GetKalshiDollarPrice(json, dollarField, centsField := "") {
    val := GetFirstNonEmptyJsonField(json, [dollarField])
    if (val != "")
        return val

    if (centsField != "") {
        val := GetFirstNonEmptyJsonField(json, [centsField])
        if (val != "" && IsNumericStr(val))
            return (val + 0) / 100.0
    }

    return ""
}

GetFirstNonEmptyJsonField(json, fields, skipZero := false) {
    for _, field in fields {
        val := JsonField(json, field)
        if (val != "") {
            if (skipZero && IsNumericStr(val) && (val + 0) = 0)
                continue
            return val
        }
    }
    return ""
}

KalshiQueryEncode(value) {
    value := StrReplace(value, "%", "%25")
    value := StrReplace(value, "+", "%2B")
    value := StrReplace(value, "/", "%2F")
    value := StrReplace(value, "=", "%3D")
    value := StrReplace(value, "&", "%26")
    value := StrReplace(value, "?", "%3F")
    value := StrReplace(value, "#", "%23")
    value := StrReplace(value, " ", "%20")
    return value
}

IsNumericStr(s) {
    s := Trim(s)
    return RegExMatch(s, "^-?\d+(\.\d+)?$")
}

JsonField(json, field) {
    pattern := """" field """\s*:\s*(""([^""]*)""|[^,}\s][^,}\r\n]*)"
    result := ""
    pos := 1
    while (pos := RegExMatch(json, pattern, m, pos)) {
        val := Trim(m1)
        val := Trim(val, """")
        if (val != "")
            result := val
        pos += StrLen(m)
    }
    return result
}

MinutesUntilIsoUtc(iso) {
    ts := IsoUtcToAhk(iso)
    if (ts = "")
        return ""

    nowUtc := CurrentUtcNowAhk()
    if (nowUtc = "")
        return ""

    diff := ts
    EnvSub, diff, %nowUtc%, Seconds
    return diff / 60.0
}

IsoUtcToAhk(iso) {
    if (iso = "")
        return ""
    if !RegExMatch(iso, "O)^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})", m)
        return ""
    return m1 m2 m3 m4 m5 m6
}
