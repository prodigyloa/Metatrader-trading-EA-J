//+------------------------------------------------------------------+
//|                                                PropPasserEA.mq5  |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Prop Firm Challenge EA — designed to pass funded account         |
//| challenges on XAUUSD, NAS100, and US30.                          |
//|                                                                  |
//| Strategies:                                                       |
//|   1. EMA Trend + Pin Bar  (default — works on all 3 instruments) |
//|   2. EMA Crossover + RSI  (alternative — better for trending)    |
//|                                                                  |
//| Funded Account Rules Engine:                                     |
//|   - Daily drawdown limit  (default 5%)                           |
//|   - Overall max drawdown  (default 10%)                          |
//|   - Profit target tracker (default 8%)                           |
//|   - Consistency rule      (optional)                             |
//|   - State persists across restarts via GlobalVariables           |
//|                                                                  |
//| Includes are loaded in dependency order (Parameters first).      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Standard library
#include <Trade\Trade.mqh>

//--- Modules (Parameters.mqh must be first — it defines all globals)
#include <Nkanven\PropPasserEA\Parameters.mqh>
#include <Nkanven\PropPasserEA\TradingHour.mqh>
#include <Nkanven\PropPasserEA\ScanPositions.mqh>
#include <Nkanven\PropPasserEA\RiskManager.mqh>
#include <Nkanven\PropPasserEA\FundedRulesManager.mqh>
#include <Nkanven\PropPasserEA\SignalEngine.mqh>
#include <Nkanven\PropPasserEA\OrderManager.mqh>
#include <Nkanven\PropPasserEA\Dashboard.mqh>

//--- Indicator handles (initialised in OnInit)
int h_ema_trend = INVALID_HANDLE;   // 50 EMA — trend filter for pin bar strategy
int h_ema_fast  = INVALID_HANDLE;   // 8  EMA — fast line for crossover strategy
int h_ema_slow  = INVALID_HANDLE;   // 21 EMA — slow line for crossover strategy
int h_atr       = INVALID_HANDLE;   // ATR — stop loss distance
int h_rsi       = INVALID_HANDLE;   // RSI — crossover strategy filter

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   ENUM_TIMEFRAMES tf = (InpTimeFrame == PERIOD_CURRENT)
                         ? (ENUM_TIMEFRAMES)Period() : InpTimeFrame;

   //--- Create indicator handles
   h_ema_trend = iMA(gSymbol, tf, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_fast  = iMA(gSymbol, tf, InpFastEmaPeriod,  0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow  = iMA(gSymbol, tf, InpSlowEmaPeriod,  0, MODE_EMA, PRICE_CLOSE);
   h_atr       = iATR(gSymbol, tf, InpAtrPeriod);
   h_rsi       = iRSI(gSymbol, tf, InpRsiPeriod, PRICE_CLOSE);

   if(h_ema_trend == INVALID_HANDLE || h_ema_fast == INVALID_HANDLE ||
      h_ema_slow  == INVALID_HANDLE || h_atr      == INVALID_HANDLE ||
      h_rsi       == INVALID_HANDLE)
     {
      Print("PropPasserEA: Failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
     }

   //--- Wire handles into SignalEngine
   g_h_ema_trend = h_ema_trend;
   g_h_ema_fast  = h_ema_fast;
   g_h_ema_slow  = h_ema_slow;
   g_h_rsi       = h_rsi;

   //--- Funded account rules — load or initialise persisted state
   LoadFundedState();

   //--- Dashboard
   InitDashboard();
   UpdateDashboard();

   Print("PropPasserEA v1.00 initialised | Symbol: ", gSymbol,
         " | TF: ", EnumToString(tf),
         " | Strategy: ", (InpStrategy == STRATEGY_EMA_PINBAR) ? "EMA+PinBar" : "EMA+Crossover",
         " | InitialBalance: ", DoubleToString(gInitialBalance, 2),
         " | DaysTraded: ", gDaysTraded);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Persist funded account state so it survives restarts
   SaveFundedState();

   //--- Release indicator handles
   if(h_ema_trend != INVALID_HANDLE) { IndicatorRelease(h_ema_trend); h_ema_trend = INVALID_HANDLE; }
   if(h_ema_fast  != INVALID_HANDLE) { IndicatorRelease(h_ema_fast);  h_ema_fast  = INVALID_HANDLE; }
   if(h_ema_slow  != INVALID_HANDLE) { IndicatorRelease(h_ema_slow);  h_ema_slow  = INVALID_HANDLE; }
   if(h_atr       != INVALID_HANDLE) { IndicatorRelease(h_atr);       h_atr       = INVALID_HANDLE; }
   if(h_rsi       != INVALID_HANDLE) { IndicatorRelease(h_rsi);       h_rsi       = INVALID_HANDLE; }

   //--- Remove dashboard labels
   DestroyDashboard();
  }

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Capture time and price
   TimeCurrent(dt);
   SymbolInfoTick(_Symbol, last_tick);

   //--- 1. Count open positions for this EA
   ScanPositions();

   //--- 2. Refresh indicator values into globals
   gAtr = GetIndValue(h_atr, 0, 1);

   //--- 3. Session / operating hours check
   CheckOperationHours();

   //--- 4. Funded account rules: daily reset, metrics, enforcement
   UpdateFundedRules();

   //--- 5. Update dashboard every tick
   UpdateDashboard();

   //--- 6. If permanently halted, do nothing else
   if(gMaxDDHit) return;

   //--- 7. If daily limit or target reached, no new entries
   if(gDailyLimitHit || gTargetReached) return;

   //--- 8. Session hours gate
   if(!gIsOperatingHours) return;

   //--- 9. Algorithmic trading must be enabled
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;

   //--- 10. Spread check
   long currentSpread = SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);
   if(currentSpread > InpMaxSpread) return;

   //--- 11. Max positions guard
   if(gTotalPositions >= InpMaxPositions) return;

   //--- 12. Get entry signal (only fires on a new closed bar)
   ENUM_MODE_TRADE_SIGNAL signal = GetSignal();
   if(signal == NO_SIGNAL) return;

   //--- 13. Execute the order
   ExecuteOrder(signal);
  }

//+------------------------------------------------------------------+
//| Track trading days via closed deal events                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
  {
   //--- We only care about deals added to history
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   //--- Must be a closing deal for our magic number
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   //--- Record this as an active trading day
   MqlDateTime now, last;
   TimeCurrent(now);
   TimeToStruct(gLastDayReset, last);

   if(now.day_of_year != last.day_of_year || now.year != last.year)
     {
      //--- Already handled by UpdateFundedRules() day reset; just increment counter
      gDaysTraded++;
      SaveFundedState();
      Print("PropPasserEA: Trading day recorded. Total: ", gDaysTraded);
     }
  }
//+------------------------------------------------------------------+
