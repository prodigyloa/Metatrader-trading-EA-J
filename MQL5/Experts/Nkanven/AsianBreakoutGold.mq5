//+------------------------------------------------------------------+
//|                                           AsianBreakoutGold.mq5 |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Asian Range Breakout EA — XAUUSD M15                             |
//|                                                                   |
//| Strategy:                                                         |
//|   1. Build Asian session range (default 23:00–06:00 server time) |
//|   2. Wait for London open breakout candle (07:00–10:00)          |
//|   3. Filter with H1 200 EMA trend direction                      |
//|   4. One trade per day; SL at range extreme + buffer             |
//|                                                                   |
//| Funded account rules are enforced via the shared modules from    |
//| PropPasserEA (RiskManager, FundedRulesManager, etc.).            |
//|                                                                   |
//| Includes are loaded in dependency order — Parameters.mqh first.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Standard library
#include <Trade\Trade.mqh>

//--- Own parameters (must be first — defines all enums, inputs, globals)
#include <Nkanven\AsianBreakoutGold\Parameters.mqh>

//--- Shared infrastructure modules (unchanged)
#include <Nkanven\PropPasserEA\TradingHour.mqh>
#include <Nkanven\PropPasserEA\ScanPositions.mqh>
#include <Nkanven\PropPasserEA\RiskManager.mqh>
#include <Nkanven\PropPasserEA\FundedRulesManager.mqh>
#include <Nkanven\PropPasserEA\OrderManager.mqh>
#include <Nkanven\PropPasserEA\Dashboard.mqh>

//--- Own signal engine (after Parameters.mqh so all globals are visible)
#include <Nkanven\AsianBreakoutGold\SignalEngine.mqh>

//--- Indicator handles (initialised in OnInit)
int h_ema_h1 = INVALID_HANDLE;   // H1 200 EMA — trend filter
int h_atr    = INVALID_HANDLE;   // ATR — lot sizing fallback

//+------------------------------------------------------------------+
//| Overwrite dashboard line 8 with live Asian range info.           |
//| Called on each new M15 bar after UpdateDashboard().              |
//+------------------------------------------------------------------+
void UpdateAsianDashboardLine()
  {
   if(!InpShowDashboard || IsTesting()) return;
   SetLabel(DashName(8),
            "Range: H=" + DoubleToString(gAsianHigh, _Digits) +
            " L="       + DoubleToString(gAsianLow,  _Digits) +
            "  Ready="  + (gAsianRangeReady ? "YES" : "NO"),
            clrSilver);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Execute a market order with full SL_RANGE support.               |
//|                                                                   |
//| When InpStopLossMode == SL_RANGE the SL is placed at the Asian   |
//| range extreme ± InpRangeSLBuffer points.  For SL_AUTO and        |
//| SL_FIXED the behaviour mirrors OrderManager::ExecuteOrder().     |
//| Uses g_orderTrade (CTrade) and CalculateLotSize() from the       |
//| shared modules included above.                                   |
//+------------------------------------------------------------------+
void ExecuteAsianOrder(ENUM_MODE_TRADE_SIGNAL signal)
  {
   if(signal == NO_SIGNAL) return;

   SymbolInfoTick(gSymbol, last_tick);
   double entryPrice = (signal == BUY_SIGNAL) ? last_tick.ask : last_tick.bid;

   //--- Compute SL distance
   double slDistance = 0.0;
   if(InpStopLossMode == SL_RANGE)
     {
      double slLevel = (signal == BUY_SIGNAL)
                       ? gAsianLow  - InpRangeSLBuffer * _Point
                       : gAsianHigh + InpRangeSLBuffer * _Point;
      slDistance = MathAbs(entryPrice - slLevel);
     }
   else if(InpStopLossMode == SL_AUTO && gAtr > 0.0)
      slDistance = gAtr * InpAtrMultiplier;
   else
      slDistance = InpDefaultStopLoss * _Point;

   if(slDistance <= 0.0)
     {
      Print("AsianBreakoutGold: SL distance is zero — skipping order");
      return;
     }

   //--- Compute TP distance
   double tpDistance = (InpTakeProfitMode == TP_AUTO)
                       ? slDistance * InpRRRatio
                       : InpDefaultTakeProfit * _Point;

   //--- Absolute SL/TP prices
   int digits = (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   double slPrice, tpPrice;
   if(signal == BUY_SIGNAL)
     {
      slPrice = NormalizeDouble(entryPrice - slDistance, digits);
      tpPrice = NormalizeDouble(entryPrice + tpDistance, digits);
     }
   else
     {
      slPrice = NormalizeDouble(entryPrice + slDistance, digits);
      tpPrice = NormalizeDouble(entryPrice - tpDistance, digits);
     }

   //--- Lot size from shared RiskManager (pass SL distance in points)
   double slPoints = slDistance / _Point;
   if(!CalculateLotSize(slPoints) || gLotSize <= 0.0)
     {
      Print("AsianBreakoutGold: Lot size calculation failed — skipping order");
      return;
     }

   //--- Configure CTrade (g_orderTrade defined in OrderManager.mqh)
   g_orderTrade.SetExpertMagicNumber(InpMagicNumber);
   g_orderTrade.SetDeviationInPoints(InpSlippage);
   g_orderTrade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Retry loop (mirrors OrderManager pattern)
   bool success = false;
   for(int attempt = 1; attempt <= gOrderOpRetry && !success; attempt++)
     {
      success = (signal == BUY_SIGNAL)
                ? g_orderTrade.Buy( gLotSize, gSymbol, entryPrice, slPrice, tpPrice, InpComment)
                : g_orderTrade.Sell(gLotSize, gSymbol, entryPrice, slPrice, tpPrice, InpComment);

      if(!success)
        {
         int err = GetLastError();
         Print("AsianBreakoutGold: Order attempt ", attempt, " failed — Error ", err);

         if(attempt == 1)
            g_orderTrade.SetTypeFilling(ORDER_FILLING_FOK);

         SymbolInfoTick(gSymbol, last_tick);
         entryPrice = (signal == BUY_SIGNAL) ? last_tick.ask : last_tick.bid;
         if(signal == BUY_SIGNAL)
           {
            slPrice = NormalizeDouble(entryPrice - slDistance, digits);
            tpPrice = NormalizeDouble(entryPrice + tpDistance, digits);
           }
         else
           {
            slPrice = NormalizeDouble(entryPrice + slDistance, digits);
            tpPrice = NormalizeDouble(entryPrice - tpDistance, digits);
           }
        }
     }

   if(success)
     {
      gLastBarTraded = iTime(gSymbol, PERIOD_M15, 1);
      gTradedToday   = true;
      Print("AsianBreakoutGold: Order placed — ", EnumToString(signal),
            " Lot=",   gLotSize,
            " Entry=", entryPrice,
            " SL=",    slPrice,
            " TP=",    tpPrice);
     }
   else
      Print("AsianBreakoutGold: All ", gOrderOpRetry, " attempts failed for ",
            EnumToString(signal));
  }

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Create indicator handles
   h_ema_h1 = iMA(gSymbol, PERIOD_H1, InpTrendEmaPeriodH1, 0, MODE_EMA, PRICE_CLOSE);
   h_atr    = iATR(gSymbol, PERIOD_M15, InpAtrPeriod);

   if(h_ema_h1 == INVALID_HANDLE || h_atr == INVALID_HANDLE)
     {
      Print("AsianBreakoutGold: Failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
     }

   //--- Wire handles into SignalEngine
   g_h_ema_h1 = h_ema_h1;

   //--- Funded account rules — load or initialise persisted state
   LoadFundedState();

   //--- Dashboard
   InitDashboard();
   UpdateDashboard();
   UpdateAsianDashboardLine();

   Print("AsianBreakoutGold v1.00 initialised | Symbol: ", gSymbol,
         " | Asian: ", InpAsianSessionStart, "-", InpAsianSessionEnd,
         " | London: ", InpLondonOpenStart, "-", InpLondonOpenEnd,
         " | H1 EMA: ", InpTrendEmaPeriodH1,
         " | InitialBalance: ", DoubleToString(gInitialBalance, 2),
         " | DaysTraded: ", gDaysTraded);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveFundedState();

   if(h_ema_h1 != INVALID_HANDLE) { IndicatorRelease(h_ema_h1); h_ema_h1 = INVALID_HANDLE; }
   if(h_atr    != INVALID_HANDLE) { IndicatorRelease(h_atr);    h_atr    = INVALID_HANDLE; }

   DestroyDashboard();
  }

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Lightweight per-tick work
   TimeCurrent(dt);
   SymbolInfoTick(_Symbol, last_tick);
   ScanPositions();

   //--- New M15 bar detection (performance gate for expensive updates)
   static datetime lastBar = 0;
   datetime currentBar = iTime(gSymbol, PERIOD_M15, 0);
   if(currentBar != lastBar)
     {
      lastBar = currentBar;

      gAtr = GetIndValue(h_atr, 0, 1);
      CheckOperationHours();
      UpdateFundedRules();
      UpdateDashboard();
      UpdateAsianDashboardLine();
     }

   //--- Range tracking runs every tick so it captures each incoming tick
   //    during the Asian session; exits immediately outside the window
   UpdateAsianRange();

   //--- Gate checks (ordered cheapest first)
   if(gMaxDDHit)                      return;
   if(gDailyLimitHit || gTargetReached) return;
   if(!gIsOperatingHours)             return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   if(SymbolInfoInteger(gSymbol, SYMBOL_SPREAD) > InpMaxSpread) return;
   if(gTotalPositions >= InpMaxPositions) return;

   //--- Signal evaluation and execution
   ENUM_MODE_TRADE_SIGNAL signal = GetSignal();
   if(signal == NO_SIGNAL) return;

   ExecuteAsianOrder(signal);
  }

//+------------------------------------------------------------------+
//| Track trading days via closed deal events                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   MqlDateTime now, last;
   TimeCurrent(now);
   TimeToStruct(gLastDayReset, last);

   if(now.day_of_year != last.day_of_year || now.year != last.year)
     {
      gDaysTraded++;
      SaveFundedState();
      Print("AsianBreakoutGold: Trading day recorded. Total: ", gDaysTraded);
     }
  }
//+------------------------------------------------------------------+
