;=====================================================================
; KALSHI AI PAPER STRATEGY
;======================================================================
assets := ["BTC"]              ; BTC, ETH, SOL, XRP, DOGE, HYPE, BNB
orderSize := 300               ; Simulated contracts per trade
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
kalshiApiBase := "https://api.elections.kalshi.com"
assetSeriesMap := { "BTC": "KXBTC15M", "ETH": "KXETH15M", "SOL": "KXSOL15M", "XRP": "KXXRP15M", "DOGE": "KXDOGE15M", "HYPE": "KXHYPE15M", "BNB": "KXBNB15M" }

; Track one open position per asset.
positions := {}
assetPhase := {}              ; WAIT_AI_WINDOW | READY_TO_ENTER | IN_POSITION | failure states
assetSessionQuarter := {}     ; quarter index currently tracked per asset
assetLastPriceLogTick := {}   ; throttled logging control
assetSnapshotCache := {}
assetMarketRefreshTick := {}
assetPriceCache := {}
assetPriceRefreshTick := {}
kalshiLastOrderResult := {}
kalshiShardFundingSessionStatus := {}
pendingModelOutcomeAudits := {}
modelOutcomeAuditLastCheckTick := {}

; Paper PnL for simulated trades opened by this script run.
kalshiRealizedPnl := 0
kalshiWins := 0
kalshiTradeCount := 0
kalshiHasUntrackedPosition := false
kalshiAverageEntryFillNotional := 0
kalshiAverageEntryFillSize := 0
kalshiAverageEntryFillOrderIds := {}
pendingKalshiSettlements := {}
pendingKalshiClosedTrades := {}
kalshiSettlementLastCheckTick := {}
dailyPnlLimitTriggered := false

Log("Application Started | PAPER MODE | " FormatAssetList(assets) " 15-minute AI direction strategy | provider: " modelProvider " | model: " modelDisplayName " | Obey model: " Obey_model " | AI request at " timeDelay "m remaining | order size: " KalshiFormatSize(orderSize) " | Agent PnL limits: " FmtPnl(Max_daily_profit) "/" FmtPnl(Max_daily_Loss))
Log("PAPER MODE | current-ask simulated fills | no live orders")
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
            assetPhase[asset] := "WAIT_AI_WINDOW"
            assetLastPriceLogTick[asset] := 0
            ns_log_once_reset(asset)
            Log(asset " New PAPER session (" snapshot.marketTicker ", shard " snapshot.exchangeIndex ")")
            LogStreamYellow("AI SIGNAL", "n/a")
            LogStreamYellow("POSITION", "SKIP")
            kalshiHasUntrackedPosition := false
        }

        if IsObject(positions[asset]) {
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

        if (assetPhase[asset] = "AI_FAILED") {
            ns_log_once(asset, "AI_FAILED", asset " " modelProvider " analysis failed, waiting for next session")
            continue
        }

        if (assetPhase[asset] = "SETTLEMENT_PENDING" || assetPhase[asset] = "SESSION_ENDED") {
            ns_log_once(asset, "SESSION_ENDED", asset " Session ended, waiting for the next market")
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
            LogStreamYellow("AI SIGNAL", aiDecision.direction)
            LogStreamYellow("POSITION", "SKIP")
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
            ns_log_once(asset, "AI_SKIPPED", asset " AI chose SKIP | no PAPER order | " aiDecision.reason)
            continue
        }
        ; Only explicit entry decisions may reach the order block.
        if (aiDecision.direction != "UP" && aiDecision.direction != "DOWN") {
            assetPhase[asset] := "AI_FAILED"
            ns_log_once(asset, "AI_INVALID", asset " Invalid AI decision; no PAPER order")
            continue
        }
        ; The model-provider request can take time, so refresh the Kalshi quote before
        ; using the selected side's current ask.
        freshSnap := GetKalshiMarketSnapshot(asset)
        if !IsObject(freshSnap) {
            ns_log_once(asset, "FRESH_QUOTE_MISSING", asset " Fresh Kalshi quote unavailable; entry will retry")
            continue
        }
        if (freshSnap.marketTicker != sessionKey) {
            assetPhase[asset] := "SESSION_ENDED"
            Log(asset " Market changed before entry; no PAPER order placed for " sessionKey)
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

        Log(asset " " ns_ai_provider(aiDecision) " " ns_ai_model_display_name(aiDecision) " chose " modelDirection " | Obey_model=" Obey_model " | trade side=" side " | current ask " Fmt(entryPrice) " — placing PAPER order")
        fillPrice := entryPrice + 0
        posSize := orderSize + 0
        entryFees := 0
        paperOrderId := "PAPER-" snapshot.marketTicker "-" side "-" A_TickCount
        initialMark := KalshiSnapshotPositionBid(snapshot, side, posSize)
        positions[asset] := { side: side, entry: fillPrice, entryFees: entryFees, size: posSize, expectedSize: posSize, accountingReady: true, entryOrderId: paperOrderId, ticker: snapshot.marketTicker, exchangeIndex: snapshot.exchangeIndex, quarterIndex: CurrentQuarterIndex(), lastMark: initialMark }
        RecordKalshiEntryFillForAverage(positions[asset])
        MarkModelOutcomeAuditOrderPlaced(asset, sessionKey, paperOrderId, side)
        positions[asset].aiDirection := modelDirection
        positions[asset].tradeDirection := side
        positions[asset].obeyModel := Obey_model
        positions[asset].aiModel := aiDecision.model
        assetPhase[asset] := "IN_POSITION"
        assetLastPriceLogTick[asset] := 0
        UpdateKalshiLogStream(asset, snapshot)
        Log(asset " PAPER position confirmed | fill " Fmt(fillPrice) " | size " KalshiFormatSize(posSize) " | simulated entry fees " FmtMoney(entryFees) " (current ask)")
        Log(asset " Holding PAPER " side " to market resolution")
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
    Log(asset " PAPER " pos.side " held to resolution | PnL settlement pending")
    positions.Delete(asset)
    LogStreamYellow("POSITION", "SKIP")
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
        LogStreamYellow(asset, FmtOrNA(livePrice))
    else
        LogStreamYellow(asset, "n/a")
    LogStreamYellow("up", FmtOrNA(snapshot.up))
    LogStreamYellow("down", FmtOrNA(snapshot.down))
    LogStreamYellow("LIVE DELTA", FmtLiveDeltaOrNA(LiveDelta))
    LogStreamYellow("AVERAGE FILL", FmtAverageFillOrNA(GetKalshiAverageFillForLogStream()))
    sessionKey := snapshot.HasKey("marketTicker") ? snapshot.marketTicker : ""
    aiDecision := ns_ai_cached_decision(asset, sessionKey)
    if IsObject(aiDecision)
        LogStreamYellow("AI SIGNAL", aiDecision.direction)
    else
        LogStreamYellow("AI SIGNAL", "n/a")
    LogStreamYellow("POSITION", GetAgentPositionForLogStream(asset))
}

GetKalshiAverageFillForLogStream() {
    global kalshiAverageEntryFillNotional, kalshiAverageEntryFillSize
    if (kalshiAverageEntryFillSize <= 0)
        return ""
    return kalshiAverageEntryFillNotional / kalshiAverageEntryFillSize
}

GetAgentPositionForLogStream(asset) {
    global positions
    if IsObject(positions[asset]) && positions[asset].HasKey("side") {
        side := positions[asset].side
        if (side = "UP" || side = "DOWN")
            return side
    }
    return "SKIP"
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

NewKalshiFillSummary() {
    return { size: 0, notional: 0, price: "", fees: 0, feesKnown: true, source: "" }
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
    if !KalshiPositionAccountingReady(pos)
        return false
    RecordKalshiEntryFillForAverage(pos)
    return true
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

    Log(asset " PAPER " pos.side " closed | entry " Fmt(pos.entry) " | exit fill " Fmt(exitPrice) " | size " KalshiFormatSize(size) " | simulated fees " FmtMoney(entryFees + exitFees) " | net PnL " FmtPnl(pnl) " | " reason)
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
            tradeStatus := audit.orderPlaced ? (InStr(audit.orderId, "PAPER-") = 1 ? "PAPER_ORDER_PLACED" : "ORDER_PLACED") : "NO_ORDER_PLACED"
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
        tradeStatus := audit.orderPlaced ? (InStr(audit.orderId, "PAPER-") = 1 ? "PAPER_ORDER_PLACED" : "ORDER_PLACED") : "NO_ORDER_PLACED"
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

    ; Paper trades fill at the observed ask, are marked at the executable bid,
    ; and use zero simulated entry/settlement fees.
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
    LogStreamYellow("LIVE PNL", FmtPnl(ComputeKalshiLivePnl()))
    LogStreamYellow("WINS", kalshiWins "/" kalshiTradeCount)
    ns_ai_refresh_balance_logstream(balanceRefreshMs)
}

NormalizeKalshiExchangeIndex(exchangeIndex) {
    exchangeIndex := Trim(exchangeIndex)
    if !RegExMatch(exchangeIndex, "^-?\d+$")
        return -1
    exchangeIndex += 0
    return (exchangeIndex >= -1) ? exchangeIndex : -1
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
