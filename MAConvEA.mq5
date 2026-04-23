//+------------------------------------------------------------------+
//|  MAConvEA.mq5                                                    |
//|  Copyright 2024                                                  |
//|  Expert Advisor driven by MAConvergenceSignal_jase indicator     |
//+------------------------------------------------------------------+
//  SETUP: compile MAConvergenceSignal_jase.mq5 into MQL5\Indicators\ first.
//  Reads buffer 0 (bull) and buffer 1 (bear) on every new bar close.
//  MODE_ZERO_CROSS signals are at buffer shift 1 (last closed bar).
//  MODE_PRE_CROSS / MODE_EXTREME signals are at buffer shift 2 (confirmed minimum).
//+------------------------------------------------------------------+
#property copyright "2024"
#property link      ""
#property version   "1.01"
#property description "Trades MAConvergenceSignal_jase bull/bear arrows"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- signal mode enum must match the indicator
enum ENUM_SIGNAL_MODE
{
   MODE_ZERO_CROSS,   // Confirmed MA cross
   MODE_PRE_CROSS,    // Minimum gap (visual cross) — default
   MODE_EXTREME,      // Peak/trough contraction
};

//--- ── Indicator parameters ──────────────────────────────────────────────────
input group "=== Indicator Settings ==="
input int              InpFastPeriod        = 5;              // Fast MA Period
input int              InpSlowPeriod        = 14;             // Slow MA Period
input ENUM_MA_METHOD   InpMAMethod          = MODE_EMA;       // MA Method
input ENUM_SIGNAL_MODE InpSignalMode        = MODE_PRE_CROSS; // Signal Mode
input int              InpLookback          = 10;             // Lookback for extreme
input double           InpExtremeMultiplier = 1.5;            // Extreme multiplier

//--- ── Trade parameters ──────────────────────────────────────────────────────
input group "=== Trade Settings ==="
input double           InpLotSize           = 0.1;            // Lot size
input int              InpStopLossPts       = 200;            // Stop loss (points, 0=off)
input int              InpTakeProfitPts     = 400;            // Take profit (points, 0=off)
input int              InpMaxSpreadPts      = 30;             // Max spread filter (points, 0=off)
input int              InpMagicNumber       = 20240001;       // Magic number
input string           InpTradeComment      = "MAConvEA";     // Order comment

//--- ── Position behaviour ────────────────────────────────────────────────────
input group "=== Position Behaviour ==="
input bool             InpFlipOnReverse     = true;           // Close & flip on opposite signal
input bool             InpOneTradeOnly      = true;           // Skip signal if same-direction trade exists

//--- ── Filters ───────────────────────────────────────────────────────────────
input group "=== Filters ==="
input int              InpMaxDailyTrades    = 3;              // Max trades per day (0=off)
input bool             InpUseTimeFilter     = false;          // Enable time filter
input int              InpSessionStart      = 7;              // Session start hour (server time)
input int              InpSessionEnd        = 20;             // Session end hour (server time)
input bool             InpUseTrendFilter    = false;          // Enable H1 200 EMA trend filter
input int              InpTrendEmaPeriod    = 200;            // Trend EMA period
input ENUM_TIMEFRAMES  InpTrendTF           = PERIOD_H1;      // Trend timeframe
input bool             InpUseATRSLTP        = false;          // Use ATR for SL/TP instead of points
input int              InpATRPeriod         = 14;             // ATR period
input double           InpATRSLMult         = 1.5;            // ATR SL multiplier
input double           InpATRTPMult         = 3.0;            // ATR TP multiplier

//--- Globals
CTrade   trade;
int      hSignal        = INVALID_HANDLE;
int      hTrend         = INVALID_HANDLE;
int      hATR           = INVALID_HANDLE;
datetime lastBarTime    = 0;
int      gDailyTradeCount = 0;
datetime gLastTradeDay    = 0;

//+------------------------------------------------------------------+
//| Normalise a price to the symbol's tick size                      |
//+------------------------------------------------------------------+
double NormalisePrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

//+------------------------------------------------------------------+
//| Count open positions for this EA on this symbol by direction     |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE dir)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == dir) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all EA positions on this symbol (optionally filter by dir) |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE dir = -1)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(dir != (ENUM_POSITION_TYPE)-1 &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != dir) continue;
      trade.PositionClose(PositionGetTicket(i));
   }
}

//+------------------------------------------------------------------+
//| Open a market order — returns true if order was accepted         |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = 0.0, tp = 0.0;

   if(InpUseATRSLTP)
   {
      double atrBuf[1];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(hATR, 0, 0, 1, atrBuf) < 1) return false;
      double atr = atrBuf[0];
      if(type == ORDER_TYPE_BUY)
      {
         sl = NormalisePrice(ask - InpATRSLMult * atr);
         tp = NormalisePrice(ask + InpATRTPMult * atr);
      }
      else
      {
         sl = NormalisePrice(bid + InpATRSLMult * atr);
         tp = NormalisePrice(bid - InpATRTPMult * atr);
      }
   }
   else
   {
      double pts = _Point;
      if(type == ORDER_TYPE_BUY)
      {
         sl = (InpStopLossPts   > 0) ? NormalisePrice(ask - InpStopLossPts   * pts) : 0.0;
         tp = (InpTakeProfitPts > 0) ? NormalisePrice(ask + InpTakeProfitPts * pts) : 0.0;
      }
      else
      {
         sl = (InpStopLossPts   > 0) ? NormalisePrice(bid + InpStopLossPts   * pts) : 0.0;
         tp = (InpTakeProfitPts > 0) ? NormalisePrice(bid - InpTakeProfitPts * pts) : 0.0;
      }
   }

   if(type == ORDER_TYPE_BUY)
      return trade.Buy(InpLotSize, _Symbol, ask, sl, tp, InpTradeComment);
   else
      return trade.Sell(InpLotSize, _Symbol, bid, sl, tp, InpTradeComment);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   hSignal = iCustom(_Symbol, _Period, "MAConvergenceSignal_jase",
                     InpFastPeriod,        // int
                     InpSlowPeriod,        // int
                     InpMAMethod,          // ENUM_MA_METHOD
                     PRICE_CLOSE,          // ENUM_APPLIED_PRICE
                     InpSignalMode,        // ENUM_SIGNAL_MODE
                     InpLookback,          // int
                     InpExtremeMultiplier, // double
                     false,                // InpShowDash
                     CORNER_LEFT_UPPER,    // InpCorner
                     200,                  // InpDashX
                     30);                  // InpDashY

   if(hSignal == INVALID_HANDLE)
   {
      Print("MAConvEA: failed to load MAConvergenceSignal_jase. ",
            "Ensure it is compiled in MQL5\\Indicators\\");
      return INIT_FAILED;
   }

   hTrend = iMA(_Symbol, InpTrendTF, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(InpUseTrendFilter && hTrend == INVALID_HANDLE)
   {
      Print("MAConvEA: failed to create trend EMA handle");
      return INIT_FAILED;
   }

   hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(InpUseATRSLTP && hATR == INVALID_HANDLE)
   {
      Print("MAConvEA: failed to create ATR handle");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("MAConvEA initialised — Magic:", InpMagicNumber,
         " Lots:", InpLotSize,
         " SL:", InpStopLossPts, "pts  TP:", InpTakeProfitPts, "pts",
         " Mode:", EnumToString(InpSignalMode));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hSignal != INVALID_HANDLE) IndicatorRelease(hSignal);
   if(hTrend  != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hATR    != INVALID_HANDLE) IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| OnTick — bar-close driven logic                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- new-bar gate: only act once per closed bar
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == lastBarTime) return;
   lastBarTime = barTime;

   //--- reset daily trade count on a new calendar day
   {
      MqlDateTime now, last;
      TimeToStruct(TimeCurrent(), now);
      TimeToStruct(gLastTradeDay,  last);
      if(now.day != last.day || now.mon != last.mon || now.year != last.year)
         gDailyTradeCount = 0;
   }

   //--- session time filter
   if(InpUseTimeFilter)
   {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      if(t.hour < InpSessionStart || t.hour >= InpSessionEnd) return;
   }

   //--- spread filter
   if(InpMaxSpreadPts > 0)
   {
      long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPts > InpMaxSpreadPts)
      {
         Print("MAConvEA: spread ", spreadPts, " > max ", InpMaxSpreadPts, " — skip");
         return;
      }
   }

   //--- daily trade cap
   if(InpMaxDailyTrades > 0 && gDailyTradeCount >= InpMaxDailyTrades) return;

   //--- read indicator buffers
   //    ZERO_CROSS arrows sit at shift 1 (last closed bar).
   //    PRE_CROSS / EXTREME arrows sit at shift 2 (confirmed minimum bar).
   int signalShift = (InpSignalMode == MODE_ZERO_CROSS) ? 1 : 2;
   int copyCount   = signalShift + 1;

   double bull[], bear[];
   ArraySetAsSeries(bull, true);
   ArraySetAsSeries(bear, true);
   ArrayResize(bull, copyCount);
   ArrayResize(bear, copyCount);

   if(CopyBuffer(hSignal, 0, 0, copyCount, bull) < copyCount) return;
   if(CopyBuffer(hSignal, 1, 0, copyCount, bear) < copyCount) return;

   bool buySignal  = (bull[signalShift] != EMPTY_VALUE);
   bool sellSignal = (bear[signalShift] != EMPTY_VALUE);

   if(!buySignal && !sellSignal) return;

   //--- trend filter (H1 200 EMA): skip if price trades against the trend
   if(InpUseTrendFilter)
   {
      double ema[1];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(hTrend, 0, 0, 1, ema) < 1) return;
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(buySignal  && price < ema[0]) return;
      if(sellSignal && price > ema[0]) return;
   }

   //--- execute trade logic
   if(buySignal)
   {
      if(InpFlipOnReverse) ClosePositions(POSITION_TYPE_SELL);
      if(!InpOneTradeOnly || !HasPosition(POSITION_TYPE_BUY))
      {
         Print("MAConvEA: BUY signal on ", _Symbol, " at ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
         if(OpenTrade(ORDER_TYPE_BUY))
         {
            gDailyTradeCount++;
            gLastTradeDay = TimeCurrent();
         }
      }
   }
   else if(sellSignal)
   {
      if(InpFlipOnReverse) ClosePositions(POSITION_TYPE_BUY);
      if(!InpOneTradeOnly || !HasPosition(POSITION_TYPE_SELL))
      {
         Print("MAConvEA: SELL signal on ", _Symbol, " at ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
         if(OpenTrade(ORDER_TYPE_SELL))
         {
            gDailyTradeCount++;
            gLastTradeDay = TimeCurrent();
         }
      }
   }
}
//+------------------------------------------------------------------+
